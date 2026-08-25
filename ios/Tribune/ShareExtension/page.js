// runs inside the page safari is showing, doing the same job as the content
// script the firefox extension injects: hand back the raw html plus the images
// the server would otherwise have to download for itself.
//
// the images are fetched here rather than on the swift side because this is the
// only context that still has the page's cookies. that is the whole reason for
// uploading them at all, since anything not sent gets downloaded by the server.
// the flip side is that these fetches answer to the page's cors rules, so
// cross-origin images without permissive headers simply fail and fall back.

var MAX_IMAGES = 100;
var MAX_IMAGE_BYTES = 4 * 1024 * 1024;
// base64 inflates by a third on the way through the extension boundary, and a
// share extension has a much smaller memory ceiling than a browser tab
var MAX_TOTAL_IMAGE_BYTES = 12 * 1024 * 1024;
var IMAGE_TIMEOUT_MS = 5000;
var TOTAL_TIMEOUT_MS = 12000;

function documentHTML(d) {
  var dt = "";
  if (d.doctype) {
    dt =
      "<!DOCTYPE " +
      d.doctype.name +
      (d.doctype.publicId ? ' PUBLIC "' + d.doctype.publicId + '"' : "") +
      (d.doctype.systemId ? ' "' + d.doctype.systemId + '"' : "") +
      ">";
  }
  return dt + "\n" + d.documentElement.outerHTML;
}

// src is what ends up in the html we upload, so the server keys off it.
// currentSrc is what the browser actually loaded (i.e. the srcset pick), so
// it's the one worth fetching & the one most likely to still be cached.
function collectImages(d) {
  var seen = {};
  var images = [];
  for (var i = 0; i < d.images.length; i++) {
    var img = d.images[i];
    var attr = img.getAttribute("src");
    if (!attr) continue;

    var src;
    try {
      src = new URL(attr, d.location.href).href;
    } catch (e) {
      continue;
    }
    if (!/^https?:/.test(src) || seen[src]) continue;

    seen[src] = true;
    var current = img.currentSrc || "";
    images.push({
      src: src,
      fetchSrc: /^https?:/.test(current) ? current : src,
    });
  }
  return images;
}

function blobToBase64(blob) {
  return new Promise(function (resolve, reject) {
    var reader = new FileReader();
    reader.onerror = function () {
      reject(new Error("read failed"));
    };
    reader.onload = function () {
      var result = String(reader.result || "");
      var comma = result.indexOf(",");
      if (comma < 0) {
        reject(new Error("not a data url"));
      } else {
        resolve(result.slice(comma + 1));
      }
    };
    reader.readAsDataURL(blob);
  });
}

function fetchImage(image, budget) {
  var controller = new AbortController();
  var timer = setTimeout(function () {
    controller.abort();
  }, IMAGE_TIMEOUT_MS);

  return fetch(image.fetchSrc, {
    credentials: "include",
    cache: "force-cache",
    signal: controller.signal,
  })
    .then(function (resp) {
      if (!resp.ok) throw new Error(resp.status + " " + resp.statusText);
      return resp.blob();
    })
    .then(function (blob) {
      // a page that answers a dead image url with an html error page still comes
      // back 200, and the epub builder has nothing useful to do with that
      if (!/^image\//.test(blob.type || ""))
        throw new Error("not an image: " + blob.type);
      if (!blob.size || blob.size > MAX_IMAGE_BYTES)
        throw new Error("unusable size " + blob.size);
      if (blob.size > budget.remaining)
        throw new Error("over the total image budget");

      budget.remaining -= blob.size;
      return blobToBase64(blob).then(function (base64) {
        return { src: image.src, mime: blob.type, base64: base64 };
      });
    })
    .catch(function (err) {
      // the server downloads whatever we leave out, so a failure here costs
      // fidelity on cookie-gated images and nothing else
      console.warn("skipping image " + image.fetchSrc + ": " + err);
      return null;
    })
    .then(function (result) {
      clearTimeout(timer);
      return result;
    });
}

// resolves with whatever has landed by the deadline rather than waiting on the
// slowest image, so one hung request can't leave the share sheet spinning
function fetchImages(images) {
  var budget = { remaining: MAX_TOTAL_IMAGE_BYTES };
  var fetched = [];

  var all = Promise.all(
    images.slice(0, MAX_IMAGES).map(function (image) {
      return fetchImage(image, budget).then(function (result) {
        if (result) fetched.push(result);
      });
    }),
  );

  var deadline = new Promise(function (resolve) {
    setTimeout(resolve, TOTAL_TIMEOUT_MS);
  });

  return Promise.race([all, deadline]).then(function () {
    return fetched;
  });
}

var Extractor = function () {};

Extractor.prototype = {
  run: function (args) {
    var d = document;
    var page = { url: d.location.href, html: documentHTML(d), images: [] };

    fetchImages(collectImages(d))
      .then(function (images) {
        page.images = images;
        args.completionFunction(page);
      })
      .catch(function () {
        // html on its own is still a usable push, so never fail the whole share
        args.completionFunction(page);
      });
  },

  finalize: function () {},
};

var ExtensionPreprocessingJS = new Extractor();
