class ArticleTagship < ApplicationRecord   #yidu
  validates :article_id, :tag_id, presence: true

  belongs_to :article
  belongs_to :tag

end
