class UsersController < ApplicationController
  layout 'blog'

  def show
    @user = User.find_by username: params[:id]
    render_404 unless @user
  end

  def edit
    
  end
end
