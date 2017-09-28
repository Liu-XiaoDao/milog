class User < ApplicationRecord
  include Securable

  USERNAME_FORMAT = /[a-zA-Z0-9\-\_]{6,25}/
  EMAIL_FORMAT = /[\w\+\-\.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+/

  USERNAME_FORMAT_REGEXP = /\A#{ USERNAME_FORMAT.source }\z/
  EAMIL_FORMAT_REGEXP = /\A#{ EMAIL_FORMAT.source }\z/i

  TIPS_USERNAME_FORMAT_MSG = 'USERNAME_FORMAT'

  validates :username, :email, :password, :state, presence: true   #这几个变量不能为空
  validates :username, length: { in: 6..25 }, #长度6-25
                       format: { with: USERNAME_FORMAT_REGEXP, message: TIPS_USERNAME_FORMAT_MSG }, #用户名格式，若错误返回这个errormessage
                       uniqueness: { case_sensitive: false }  #唯一性检测，不区分大小写
  validates :email,    length: { maximum: 255 },  #最长为255
                       format: { with: EAMIL_FORMAT_REGEXP }, #格式检测
                       uniqueness: { case_sensitive: false }  #唯一性检测，不区分大小写
  validates :password, length: { minimum: 6 },  #密码最短6位
                       allow_nil: false  #为空也不跳过
  validate :avatar_size    #这个不检测

  has_many :articles,             dependent: :destroy    #有多篇文章，如果用户被删除，文章也删除
  has_many :user_categoryships,   dependent: :destroy    #有多个xx，如果用户被删除，xx也删除
  has_many :categories,           through: :user_categoryships   #通过上面有多个分类
  has_many :pictures,             dependent: :destroy     #有多张图片，用户删除图片删除
  has_many :comments,             dependent: :destroy     #有多条评论，删除用户删除评论
  has_one  :resume,               dependent: :destroy     #一个个人简介，删除也删除
  has_many :holds,                dependent: :destroy

  has_many :followingships,       class_name: 'Usership',   #  ????
                                  foreign_key: 'follower_id',
                                  dependent: :destroy
  has_many :following,            through: :followingships, source: :following
  has_many :followerships,        class_name: 'Usership',
                                  foreign_key: 'following_id',
                                  dependent: :destroy
  has_many :followers,            through: :followerships,  source: :follower

  has_many :notifications,        dependent: :destroy  #有多条通知，。。。。

  # 需引入gem bcrypt
  has_secure_password #  ????

  # 将avatar字段提交至AvatarUploader
  mount_uploader :avatar, AvatarUploader #  ????

  before_save :downcase_username_and_email      #字面意思是变成小写，保存之前
  after_create :generate_activation_digest,     #create之后
               :generate_default_category_ship,
               :generate_a_resume,
               :generate_article_and_resume_holds

  attr_accessor :remember_token, :activation_token, :reset_password_token

  scope :normal, ->{ where state: 1 }
  scope :admin, ->{ where state: 2 }
  scope :disabled, ->{ where state: 0 }
  scope :abled, ->{ where 'state = 1 OR state = 2' }

  # 生成对应属性的加密字段digest, 并保留token
  def new_attr_digest(attribute)
    send "#{attribute}_token=", new_token
    update_digest attribute, digest_token(send("#{attribute}_token"))
  end

  def del_attr_digest(attribute)
    send "#{attribute}_token=", nil
    update_digest attribute, nil
  end

  # 判断有时效的加密字段是否还生效
  def digest_expired?(attribute, deadline = 2.hours)
    start_time = send "#{attribute}_at"
    Time.zone.now - start_time > deadline
  end

  # 激活用户
  def active
    del_attr_digest :activation
    update_attribute :activated, true
    update_attribute :activated_at, Time.zone.now
  end

  # 生成激活字段, 记录用户状态
  def generate_activation_digest
    new_attr_digest :activation
    update_attribute :activated_at, Time.zone.now
  end

  # 生成重置密码字段
  def generate_reset_password_digest
    new_attr_digest :reset_password
    update_attribute :reset_password_at, Time.zone.now
  end

  # 用户已上传头像?
  def user_avatar?
    return false if avatar.file.nil?
    true
  end

  # 通过update_attribute实现update_attributes
  # 绕过验证
  def update_attributes_by_each(params)
    return false unless params
    params.each { |attri, value| update_attribute attri, value }
    true
  end

  # 用户发布文章所用的标签
  def tags
    Tag.find_by_sql [
      " SELECT  DISTINCT tags.id, tags.name
        FROM    users, articles, article_tagships, tags
        WHERE   users.id = ?
        AND     users.id = articles.user_id
        AND     articles.id = article_tagships.article_id
        AND     article_tagships.tag_id = tags.id
        AND     articles.posted = true
      ", self.id ]
  end

  # 清除缓存图片
  def delete_cache_pictures
    pictures.where(posted: false).each do |picture|
      picture.destroy
    end
  end

  # 标记图片已使用
  def post_cache_pictures
    cache_pictures = pictures.where posted: false
    if cache_pictures.any?
      cache_pictures.update_all posted: true
    end
  end

  # 关联文章/评论/简介与图片
  # 当文章等删除时, 可将使用的图片一起删除
  def post_cache_pictures_in(name, picturable)
    return if picturable.blank?
    cache_pictures = pictures.where posted: false
    if cache_pictures.any?
      cache_pictures.each do |picture|
        picturable.send("#{name}_pictureships").create picture: picture
      end
      cache_pictures.update_all posted: true
    end
  end

  # 定义关联图片方法
  # post_cache_pictures_in_article
  # post_cache_pictures_in_comment
  # post_cache_pictures_in_resume
  def self.define_post_cache_pictures_in(name)
    define_method("post_cache_pictures_in_#{name}") do |picturable|
      post_cache_pictures_in name, picturable
    end
  end

  define_post_cache_pictures_in :article
  define_post_cache_pictures_in :comment
  define_post_cache_pictures_in :resume

  # 用户禁用?
  def disabled?
    self.state == 0
  end

  # 获取文章/简历缓存
  # type in [Article, Resume]
  def hold(type)
    return nil if type.blank?
    type = type.to_s.capitalize
    return nil unless Hold::ALLOWED_HOLDABLE_TYPES.include? type
    holds.where(holdable_type: type).first
  end

  # 管理员
  def admin?
    return self.state == 2
  end

  # 是否关注了某用户
  def followed?(user)
    return false if user.blank?
    self.followingships.where(following_id: user.id).any?
  end

  def letter_avatar_url(size)
    path = LetterAvatar.generate(self.username, size).sub('public/', '/')
    "#{Setting.base_url}#{path}"
  end

  private
    #用户名邮箱变成小写
    def downcase_username_and_email
      username.downcase!
      email.downcase!
    end

    # 限制头像大小
    def avatar_size
      if avatar.size > 1.megabytes
        errors.add :avatar, I18n.t("errors.avatar_too_big", size: 1)
      end
    end

    # 生成与'默认'分类的关系
    def generate_default_category_ship
      category = Category.find_or_create_by name: 'default'
      self.user_categoryships.create category: category
    end

    # 生成简历
    def generate_a_resume
      return if self.resume
      Resume.create user: self
    end

    # 生成文章和简历的暂存
    def generate_article_and_resume_holds
      return if self.holds.size > 2
      self.holds.create holdable_type: Article.name
      self.holds.create holdable_type: Resume.name
    end
end
