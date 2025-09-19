export interface APINewsletters {
  meta: Meta;
  result: Result[];
}

export interface Meta {
  after_timestamp?: string;
  after_id?: string;
  before_timestamp?: string;
  before_id?: string;
}

export interface Result {
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
}
