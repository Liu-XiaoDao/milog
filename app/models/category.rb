class Category < ApplicationRecord  #yidu 

  validates :name,    uniqueness: { case_sensitive: false },
                      length: { maximum: 8 },
                      presence: true

  has_many :articles
  has_many :user_categoryships,  dependent: :destroy
  has_many :users,               through: :user_categoryships

  default_scope -> { order id: :asc }

  before_save :downcase_name

  # 默认分类
  DEFAULT = %w(default 默认)

  def posted_articles(user)
    return nil if user.blank?
    articles.where(user: user, posted: true)
  end

  def mname #返回名字
    return I18n.t 'categories.default' if self.name == 'default'
    self.name
  end

  class << self   #定义的是类方法
    # 已有文章使用中的分类
    def used
      _result = self.find_by_sql "
        SELECT DISTINCT categories.id, categories.name
        FROM  categories
        LEFT OUTER JOIN articles
        ON categories.id = articles.category_id
        WHERE articles.category_id IS NOT NULL
      "
      self.where id: _result
    end

    # 未有文章使用的分类
    def unused
      _result = self.find_by_sql "
        SELECT DISTINCT categories.id, categories.name
        FROM  categories
        LEFT OUTER JOIN articles
        ON categories.id = articles.category_id
        WHERE articles.category_id IS NULL
      "
      self.where id: _result
    end
  end

  private
    # 名字变小写
    def downcase_name
      name.downcase!
    end
end
