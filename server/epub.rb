# frozen_string_literal: true

require 'cgi'
require 'nokogiri'
require 'open3'
require 'securerandom'
require 'uri'
require 'zip'

EPUB_MIME = 'application/epub+zip'
CONTAINER_XML = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
      <rootfile full-path="OEBPS/Content.opf" media-type="application/oebps-package+xml"/>
    </rootfiles>
  </container>
XML
ARTICLE_NCX = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
  <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="en">
    <head>
      <meta name="dtb:uid" content="%<uuid>s" />
      <meta name="dtb:depth" content="2" />
      <meta name="dtb:totalPageCount" content="0" />
      <meta name="dtb:maxPageNumber" content="0" />
      <meta name="dtb:generator" content="some shoddy python code" />
    </head>
    <docTitle><text>%<title>s</text></docTitle>
    <docAuthor><text>%<author>s</text></docAuthor>

    <navMap>
      <navPoint id="file_0" playOrder="1">
        <navLabel><text>%<title>s</text></navLabel>
        <content src="article.html" />
      </navPoint>
    </navMap>
  </ncx>
XML
CONTENT_OPF = <<~XML
  <?xml version="1.0" encoding="utf-8"?>
  <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="2.0">
    <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:opf="http://www.idpf.org/2007/opf" xmlns:dcterms="http://purl.org/dc/terms/">
      <dc:title>%<title>s</dc:title>
      <dc:creator>%<author>s</dc:creator>
      <dc:language>en</dc:language>
      <dc:identifier id="BookId">%<uuid>s</dc:identifier>
    </metadata>
    <manifest>
      <item id="ncx" href="article.ncx" media-type="application/x-dtbncx+xml" />
      <item id="file_0" href="article.html" media-type="application/xhtml+xml"/>
      %<manifest>s
    </manifest>
    <spine toc="ncx">
      <itemref idref="file_0" />
    </spine>
  </package>
XML
HTML_BEGIN = <<~XML
  <?xml version="1.0" encoding="utf-8"?>
  <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
  <html xmlns="http://www.w3.org/1999/xhtml">
    <head>
      <title>%<title>s</title>
    </head>
    <body dir="ltr">
XML
HTML_END = <<~XML
  </body>
  </html>
XML

IMAGE_MIMES = {
  'image/gif' => '.gif',
  'image/jpeg' => '.jpg',
  'image/png' => '.png'
}.freeze
CONVERT_IMAGE_MIMES = Set.new(['image/webp', 'image/svg+xml'])
DETECT_MIMES = Set.new(['application/octet-stream'])
SKIP_MIMES = Set.new(['text/html'])
USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/50.0.2661.102 Safari/537.36'

class Epub
  def self.generate(title, author, clean_html, epub_path)
    uuid = SecureRandom.uuid
    format_vars = { uuid: uuid, title: CGI.escapeHTML(title), author: CGI.escapeHTML(author) }
    Zip::File.open(epub_path, create: true) do |zipfile|
      zipfile.get_output_stream('mimetype') { |f| f.write(EPUB_MIME) }
      zipfile.get_output_stream('META-INF/container.xml') { |f| f.write(CONTAINER_XML) }
      zipfile.get_output_stream('OEBPS/article.ncx') { |f| f.write(ARTICLE_NCX % format_vars) }

      manifest = +''
      base_html = (HTML_BEGIN % format_vars) + clean_html + HTML_END
      img_idx = 0
      doc = Nokogiri::XML(base_html)

      doc.css('img').each do |img|
        get_image(zipfile, img, manifest, img_idx)
        img_idx += 1
      rescue StandardError => e
        puts "discarding image #{img}: #{e.full_message}"
        img.remove
        next
      end

      format_vars[:manifest] = manifest
      zipfile.get_output_stream('OEBPS/article.html') { |f| f.write(doc.to_xhtml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)) }
      zipfile.get_output_stream('OEBPS/Content.opf') { |f| f.write(CONTENT_OPF % format_vars) }
    end
    uuid
  end

  def self.get_image(zipfile, img, manifest, img_idx)
    src = img['src']
    raise "Invalid img src #{src}" unless src&.start_with?('http://', 'https://')

    uri = URI.parse(src)
    res = fetch(uri)
    img_content = res.body
    content_type = res['Content-Type'].split(';').first
    suffix = File.extname(uri.path)
    img_id = "img_#{img_idx}"

    raise "#{src} has type #{content_type}, skipping" if SKIP_MIMES.include?(content_type)

    if DETECT_MIMES.include?(content_type)
      old = content_type
      content_type = detect_mime(img_content)
      puts "detected #{src} mime, #{old} => #{content_type}"
    end

    if CONVERT_IMAGE_MIMES.include?(content_type)
      puts "converting #{content_type} to jpeg"
      content_type = 'image/jpeg'
      suffix = '.jpg'
      img_content = convert_to_jpeg(img_content)
    elsif IMAGE_MIMES.key?(content_type)
      suffix = IMAGE_MIMES[content_type]
    else
      raise "invalid mime #{src} => #{content_type}"
    end

    new_path = "#{img_idx}#{suffix}"
    img['src'] = new_path

    zipfile.get_output_stream("OEBPS/#{new_path}") { |os| os.write(img_content) }

    manifest << %(<item id="#{img_id}" href="#{new_path}" media-type="#{content_type}" />)
    puts "#{new_path} <= #{src} (#{content_type})"
  end

  def self.fetch(uri, limit = 10)
    raise ArgumentError, 'Too many HTTP redirects' if limit.zero?

    res = Net::HTTP.get_response(uri)
    case res
    when Net::HTTPRedirection
      location = res['Location']
      puts "redirected to #{location}"
      fetch(URI(location), limit - 1)
    else
      res
    end
  end

  def self.detect_mime(img_content)
    stdout, stderr, status = Open3.capture3('file', '--mime', '-b', '-', stdin_data: img_content, binmode: true)
    raise "file type detection failed: #{stderr}" unless status.success?

    stdout.to_s.split(';').first.strip
  end

  def self.convert_to_jpeg(img_content)
    stdout, stderr, status = Open3.capture3('convert', '-', 'JPG:-', stdin_data: img_content, binmode: true)
    raise "convert to jpeg failed: #{stderr}" unless status.success?

    stdout
  end
end
