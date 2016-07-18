class SessionsController < ApplicationController
  # before_action :require_signed_in!, only: [:destroy]
  skip_before_action :require_signed_in!, only: [:new, :create]

  def new
    redirect_to user_index_url if signed_in?
  end

  def create
    @user = User.find_by_credentials(params[:user])
    if @user
      sign_in!(@user)
      redirect_to user_index_url
    else
      flash[:error] = "Invalid email and/or password"
      render :new
    end
  end

  def destroy
    sign_out!
    redirect_to login_url
  end

end
