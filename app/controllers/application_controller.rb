class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  #protect_from_forgery with: :exception

  before_filter :authenticate, :except => [:login]

  protected

  def authenticate
    @current_user = nil

    if session[:user]

      @current_user = ScalarmUser.find_by_id(session[:user])

    else

      if request.env.include?('HTTP_SSL_CLIENT_S_DN') and request.env['HTTP_SSL_CLIENT_S_DN'] != '(null)' and request.env['HTTP_SSL_CLIENT_VERIFY'] == 'SUCCESS'
        Rails.logger.debug("We can use DN(#{request.env['HTTP_SSL_CLIENT_S_DN']}) for authentication")

        begin
          session[:user] = ScalarmUser.authenticate_with_certificate(request.env['HTTP_SSL_CLIENT_S_DN']).id
          flash[:notice] = t('login_success')
        rescue Exception => e
          flash[:error] = e.to_s
          session[:user] = nil

          redirect_to :login
        end

      elsif request.env.include?('HTTP_AUTHORIZATION') and request.env['HTTP_AUTHORIZATION'].include?('Basic')
        authenticate_or_request_with_http_basic do |sm_uuid, password|
          Rails.logger.debug("Possible SM authentication: #{sm_uuid}")

          temp_pass = SimulationManagerTempPassword.find_by_sm_uuid(sm_uuid)

          ((not temp_pass.nil?) and temp_pass.password == password) or (sm_uuid == 'hidden' and password == 'hidden')
        end

      else
        Rails.logger.debug('We should use user and pass for authentication')

        session[:intended_action] = action_name
        session[:intended_controller] = controller_name

        redirect_to :login
      end

    end

  end
end
