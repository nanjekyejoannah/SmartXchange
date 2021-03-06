# == Schema Information
#
# Table name: users
#
#  id                    :integer          not null, primary key
#  email                 :string           not null
#  name                  :string           default("New User"), not null
#  age                   :integer          default(25), not null
#  language              :string           default("Spanish"), not null
#  language_level        :integer          default(3), not null
#  password_digest       :string           not null
#  session_token         :string           not null
#  image                 :string
#  active                :boolean          default(FALSE), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  title                 :string           default("Please fill in your profession"), not null
#  provider              :string
#  uid                   :string
#  location              :string
#  latitude              :float
#  longitude             :float
#  nationality           :string           default("Spanish"), not null
#  matches_token         :string
#  matches_sent_at       :datetime
#  braintree_customer_id :string
#  person_of_interest    :boolean          default(FALSE), not null
#  tutor                 :boolean          default(FALSE), not null
#

#active is for instantaneous feature Tati talked about

class User < ApplicationRecord
  validates_presence_of :email, :name, :age, :language, :language_level, :title, :password_digest, :session_token, :nationality
  validates :email, uniqueness: true, length: {maximum: 255}, format: {:with => /\A[^@\s]+@([^@\s]+\.)+[^@\s]+\z/i, on: :create}
  validates :password, length: { minimum: 5, maximum: 50, allow_nil: true }
  validates :title, length: {minimum: 5, maximum: 255}
  validates :name, uniqueness: true, length: {minimum: 2, maximum: 255}
  validates :age, numericality: { only_integer: true }
  validates :language_level, numericality: {only_integer: true} #may change this since it's a dropdown
  # to prevent nil values in boolean field, according to stackoverflow
  validates :person_of_interest, :tutor, :inclusion => {:in => [true, false]}
  mount_uploader :image, AvatarUploader

  has_many :notifications, :foreign_key => :notified_id, dependent: :destroy
  has_many :created_notifications, :foreign_key => :notifier_id, class_name: 'Notification', dependent: :destroy
  has_many :posts_notifications, -> { where read: false, notifiable_type: 'Post'}, :foreign_key => :notified_id, class_name: 'Notification'
  has_many :chat_rooms_notifications, -> { where read: false, notifiable_type: 'ChatRoom'}, :foreign_key => :notified_id, class_name: 'Notification'
  # keeping this for the dependent destroy aspect
  has_many :initiated_chat_rooms, :foreign_key => :initiator_id, class_name: 'ChatRoom', dependent: :destroy
  has_many :received_chat_rooms, :foreign_key => :recipient_id, class_name: 'ChatRoom', dependent: :destroy
  has_many :sent_messages, :foreign_key => :sender_id, class_name: 'Message', dependent: :destroy
  has_one :linkedin, dependent: :destroy
  has_many :posts, :foreign_key => :owner_id, class_name: 'Post', dependent: :destroy
  has_many :comments, :foreign_key => :owner_id, class_name: 'Comment', dependent: :destroy
  has_many :votes, :foreign_key => :owner_id, class_name: 'Vote', dependent: :destroy
  has_many :follows, :foreign_key => :follower_id, class_name: 'Follow', dependent: :destroy
  has_many :followed_posts, through: :follows, source: :followable, source_type: 'Post'
  has_many :reads, dependent: :destroy
  has_many :read_boards, through: :reads, source: :readable, source_type: 'Board'
  # for now can only purchase one package, may change this to feature add-ons to purchases
  has_one :purchase, :foreign_key => :buyer_id, dependent: :destroy
  has_one :package, through: :purchase
  has_one :email_subscription, dependent: :destroy
  has_many :reviews, as: :reviewable, dependent: :destroy
  has_many :created_reviews, :foreign_key => :reviewer_id, class_name: 'Review', dependent: :destroy

  geocoded_by :location

  before_save :downcase_email
  after_validation :geocode, if: :location_present_and_changed
  after_validation :lat_changed?
  after_create :add_email_subscription

  default_scope -> { order(created_at: :asc) } #may refactor take this out, asc want longest users around first

  attr_reader :password
  after_initialize :ensure_session_token

  def self.find_by_credentials(user_params)
    user = User.find_by_email(user_params[:email].downcase)
    if user && user.try(:is_password?, user_params[:password])
      return user
    elsif user
      return user.email
    else
      return nil
    end
  end

  def self.new_token
    SecureRandom.urlsafe_base64(16)
  end

  def self.create_with_omniauth(auth)
    # ensures email uniqueness validation through if statement in previous method
    # will set password as uid, hack job need to refactor
    # taking the first public Url image, assuming this is the most recent, not working at moment refactor
    user = User.create!(
      email: auth['info']['email'],
      password: auth['uid'],
      name: auth['info']['name'],
      title: auth['info']['description'],
      image: auth['extra']['raw_info']['pictureUrls'].values.second[0],
      provider: auth['provider'],
      uid: auth['uid'],
      location: auth['info']['location']['name']
    )
    # may implement positions, specialties and more once these start working
    Linkedin.create!(
      user_id: user.id,
      public_url: auth['info']['urls'].public_profile,
      industry: auth['extra']['raw_info']['industry'],
      summary: auth['extra']['raw_info']['summary']
    )
    user
  end

  def add_with_omniauth(auth)
    # doesn't need error messages because fields can be blank (except Linkedin user_id which should not throw error unless there is no current_user in which case there would be an error earlier on)
    self.update(
      provider: auth['provider'],
      uid: auth['uid'],
      location: auth['info']['location']['name']
    )
    Linkedin.create!(
      user_id: self.id,
      public_url: auth['info']['urls'].public_profile,
      industry: auth['extra']['raw_info']['industry'],
      summary: auth['extra']['raw_info']['summary']
    )
  end

  def update_with_omniauth(auth)
    # doesn't need error messages because fields can be blank
    # keeping provider and uid there because maybe the person has a new linkedin account
    # not updating password if uid changes because user might have sign in without linkedin
    self.update(
      provider: auth['provider'],
      uid: auth['uid'],
      location: auth['info']['location']['name']
    )
    self.linkedin.update(
      public_url: auth['info']['urls'].public_profile,
      industry: auth['extra']['raw_info']['industry'],
      summary: auth['extra']['raw_info']['summary']
    )
  end

  def password=(password)
    @password = password
    self.password_digest = BCrypt::Password.create(password)
  end

  def is_password?(password)
    BCrypt::Password.new(self.password_digest).is_password?(password)
  end

  def reset_token!
    self.session_token = User.new_token
    self.save!
    self.session_token
  end

  def appear
    p "appear called in user"
    self.active = true
    self.save!
  end

  def disappear
    p "disappear called in user"
    self.active = false
    self.save!
  end

  def sort_method
    User.where(language: self.language).where.not(id: self.id).includes(:linkedin).sort {|u1, u2| u2.sort_value(self) <=> u1.sort_value(self) }
  end

  def sort_value(base_user)
    denominator = self.language_level > base_user.language_level ? (self.language_level.to_f * 2) : (base_user.language_level.to_f * 2)
    sort = (self.language_level.to_f + base_user.language_level.to_f) / denominator
    # using latitude in case there was a failed geocode on location, precaution but better this way
    sort *= 1.5 if base_user.latitude && self.latitude && base_user.distance_from(self) < 50
    sort
  end

  def create_matches_token!
    self.matches_token = User.new_token
    self.matches_sent_at = Time.zone.now
    self.save!
    self.matches_token
  end

  def subscribe_to_premium
    # assuming can only subscribe to the premium package (2nd package) for now, for this and premium?  method
    self.package = Package.second
  end

  def unsubscribe_to_premium
    self.package = Package.first
  end

  def has_payment_info?
    self.braintree_customer_id
  end

  def premium?
    self.package == Package.second
  end

  def chat_bot?
    self.id == 6
  end

  protected

  def ensure_session_token
    self.session_token ||= User.new_token
  end

  def downcase_email
    self.email = self.email.downcase
  end

  def location_present_and_changed
    return true if (self.location.present? && self.location_changed?)
    return false
  end

  def lat_changed?
    # for some reason need to return at the end
    if self.location_changed?
        if !self.latitude_changed?
            self.errors.add(:location, "is not valid")
            return false
        end
    end
    return true
  end

  def add_email_subscription
    EmailSubscription.create!(user_id: self.id)
  end


end
