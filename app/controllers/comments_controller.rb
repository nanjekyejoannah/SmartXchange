class CommentsController < ApplicationController
  include UsersHelper
  include PostsHelper
  include BoardsHelper

  before_action :comment_limit, only: [:create]
  before_action :correct_comment?, only: [:update, :destroy]
  after_action -> { board_mark_read(@comment.commentable.board) }

  def create
    @comment = current_user.comments.new(comment_params)
    if @comment.save
      # assuming that the comment is for a post, will have to add code if add comment on a comment
      @post = @comment.commentable
      post_create_follow(@post)
      post_create_notifications(@comment, @post)
      respond_to do |format|
        format.js
      end
    else
      respond_to do |format|
        format.js {render "errors"}
      end
    end
  end

  def update
    @comment = Comment.find(params[:id])
    if @comment.update(comment_params)
      post_create_notifications(@comment, @comment.commentable)
      respond_to do |format|
        format.js
      end
    else
      respond_to do |format|
        format.js {render "errors"}
      end
    end
  end

  def destroy
    @comment = Comment.find(params[:id])
    @comment.destroy
    respond_to do |format|
      format.js
    end
  end

  private

  def comment_params
    params.require(:comment).permit(:content, :commentable_type, :commentable_id)
  end

  def comment_limit
    @limit = 10
    if current_user.comments.count >= @limit && current_user.comments.order(created_at: :desc).limit(@limit).last.created_at > 24.hours.ago
      respond_to do |format|
        format.js {render "comment_limit"}
      end
      return false
    end
    true
  end

  def correct_comment?
    comment = Comment.find(params[:id])
    unless comment.owner == current_user
      flash[:error] = "Unauthorized access"
      redirect_to root_path
    end
  end

end
