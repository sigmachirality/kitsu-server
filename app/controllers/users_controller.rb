class UsersController < ApplicationController
  include CustomControllerHelpers

  skip_after_action :enforce_policy_use, only: %i[recover conflicts_index conflicts_update]

  def recover
    query = params[:username]
    reset = PasswordResetService.new(query)
    reset.send!
    render json: { username: query }
  rescue PasswordResetService::EmailMissingError
    render_jsonapi_error(400, 'No username provided')
  rescue PasswordResetService::UserNotFoundError
    render_jsonapi_error(400, 'No user found')
  end

  def confirm
    token = Doorkeeper::AccessToken.by_token(params[:token])
    return render_jsonapi_error(403, 'Not Authorized') unless token&.acceptable?(:email_confirm)
    token.resource_owner.update(confirmed_at: Time.now)
    render json: { confirmed: true }
  end

  def unsubscribe
    query = params[:email]
    user = User.by_email(query).first
    user.update!(subscribed_to_newsletter: false)
    render json: { email: query }
  end

  def conflicts_index
    return render_jsonapi_error(403, 'Feature disabled') unless Flipper.enabled?(:aozora)
    conflict_detector = Zorro::UserConflictDetector.new(user: user)
    render json: conflict_detector.accounts
  end

  def conflicts_update
    return render_jsonapi_error(403, 'Feature disabled') unless Flipper.enabled?(:aozora)
    render_jsonapi_error 400, 'You must choose' unless params[:chosen].present?
    chosen = params[:chosen].to_sym
    conflict_resolver = Zorro::UserConflictResolver.new(user)
    user = conflict_resolver.merge_onto(chosen)
    render_jsonapi serialize_model(user)
  end

  def alts
    user = current_user&.resource_owner
    return render_jsonapi_error(401, 'Not permitted') unless user&.admin?
    target_user = User.find(params[:id])
    alts = target_user.alts.map { |u| { slug: u.slug, name: u.name, id: u.id } }
    render json: alts
  end

  def profile_strength
    user = current_user&.resource_owner
    user_id = params.require(:id).to_i
    unless user&.id == user_id
      return render_jsonapi serialize_error(401, 'Not permitted'), status: 401
    end

    # Get strength from Stream
    strength = RecommendationsService::Media.new(user).strength
    render json: strength, status: 200
  end

  def flags
    user = current_user&.resource_owner
    features = Flipper.preload_all
    flags = features.map { |f| [f.name, f.enabled?(user)] }.to_h
    enabled_flags = flags.select { |_, enabled| enabled }
    render json: enabled_flags, status: 200
  end
end
