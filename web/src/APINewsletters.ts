export interface APINewsletters {
  meta: APIMeta;
  result: APINewsletter[];
}

export interface APIMeta {
  after_timestamp?: string;
  after_id?: string;
  before_timestamp?: string;
  before_id?: string;
}

export interface APINewsletter {
  id: number;
  title: string;
  author: string;
  source_mime_type: string;
  read: boolean;
  deleted: boolean;
  progress: string;
  created_at: string;
  updated_at: string;
  epub_updated_at: string;
  source_updated_at: string;
}
