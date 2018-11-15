require 'spec_helper'

describe CommentsController do
  include LoginMacros
  include RedirectExpectationHelper

  let(:comment) { create(:comment) }
  let(:unreviewed_comment) { create(:unreviewed_comment) }

  before(:each) do
    request.env["HTTP_REFERER"] = "/where_i_came_from"
  end

  describe "GET #add_comment_reply" do
    context "when comment is unreviewed" do
      it "redirects logged out user to login path with an error" do
        get :add_comment_reply, params: { comment_id: unreviewed_comment.id }
        it_redirects_to_with_error(login_path, "Sorry, you cannot reply to an unapproved comment.")
      end

      it "redirects logged in user to root path with an error" do
        fake_login
        get :add_comment_reply, params: { comment_id: unreviewed_comment.id }
        it_redirects_to_with_error(root_path, "Sorry, you cannot reply to an unapproved comment.")
      end
    end

    context "when comment is not unreviewed" do
      it "redirects to the comment on the commentable without an error" do
        get :add_comment_reply, params: { comment_id: comment.id }
        expect(flash[:error]).to be_nil
        expect(response).to redirect_to(work_path(comment.ultimate_parent, show_comments: true, anchor: "comment_#{comment.id}"))
      end

      it "redirects to the comment on the commentable with the reply form open and without an error" do
        get :add_comment_reply, params: { comment_id: comment.id, id: comment.id }
        expect(flash[:error]).to be_nil
        expect(response).to redirect_to(work_path(comment.ultimate_parent, add_comment_reply_id: comment.id, show_comments: true, anchor: "comment_#{comment.id}"))
      end
    end

    context "when the commentable is a comment on a work hidden by an admin" do
      let(:work) { comment.ultimate_parent }

      before { work.update_column(:hidden_by_admin, true) }

      context "when logged out" do
        it "redirects to the home page with an error" do
          get :add_comment_reply, params: { comment_id: comment.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach. Please log in.")
        end
      end

      context "when logged in as a random user" do
        it "redirects to the home page with an error" do
          fake_login
          get :add_comment_reply, params: { comment_id: comment.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach.")
        end
      end

      context "when logged in as the comment writer" do
        it "redirects to the home page with an error" do
          fake_login_known_user(comment.pseud.user)
          get :add_comment_reply, params: { comment_id: comment.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach.")
        end
      end

      context "when logged in as the work's owner" do
        it "redirects to the work with an error" do
          fake_login_known_user(work.users.first)
          get :add_comment_reply, params: { comment_id: comment.id }
          it_redirects_to_with_error(work_path(work), "Sorry, you can't add or edit comments on a hidden work.")
        end
      end

      context "when logged in as an admin" do
        it "redirects to the work with an error" do
          fake_login_admin(create(:admin))
          get :add_comment_reply, params: { comment_id: comment.id }
          it_redirects_to_with_error(work_path(work), "Sorry, you can't add or edit comments on a hidden work.")
        end
      end
    end
  end

  describe "GET #unreviewed" do
    let!(:user) { create(:user) }
    let!(:work) { create(:work, authors: [user.default_pseud], moderated_commenting_enabled: true ) }
    let(:comment) { create(:unreviewed_comment, commentable_id: work.id) }

    it "redirects logged out users to login path with an error" do
      get :unreviewed, params: { comment_id: comment.id, work_id: work.id }
      it_redirects_to_with_error(login_path, "Sorry, you don't have permission to see those unreviewed comments.")
    end

    it "redirects to root path with an error when logged in user does not own the commentable" do
      fake_login
      get :unreviewed, params: { comment_id: comment.id, work_id: work.id }
      it_redirects_to_with_error(root_path, "Sorry, you don't have permission to see those unreviewed comments.")
    end

    it "renders the :unreviewed template for a user who owns the work" do
      fake_login_known_user(user)
      get :unreviewed, params: { work_id: comment.commentable_id }
      expect(response).to render_template("unreviewed")
    end

    it "renders the :unreviewed template for an admin" do
      fake_login_admin(create(:admin))
      get :unreviewed, params: { work_id: comment.commentable_id }
      expect(response).to render_template("unreviewed")
    end
  end

  describe "POST #new" do
    it "errors if the commentable is not a valid tag" do
      post :new, params: { tag_id: "Non existent tag" }
      expect(flash[:error]).to eq "What did you want to comment on?"
    end

    it "renders the :new template if commentable is a valid admin post" do
      admin_post = create(:admin_post)
      post :new, params: { admin_post_id: admin_post.id }
      expect(response).to render_template("new")
      expect(assigns(:name)).to eq(admin_post.title)
    end

    context "when the commentable is a valid tag" do
      let(:fandom) { create(:fandom) }

      context "when logged in as an admin" do
        before { fake_login_admin(create(:admin)) }

        it "renders the :new template" do
          post :new, params: { tag_id: fandom.name }
          expect(response).to render_template("new")
          expect(assigns(:name)).to eq("Fandom")
        end
      end

      context "when logged in as a tag wrangler" do
        before do
          fake_login
          @current_user.roles << Role.new(name: 'tag_wrangler')
        end

        it "renders the :new template" do
          post :new, params: { tag_id: fandom.name }
          expect(response).to render_template("new")
          expect(assigns(:name)).to eq("Fandom")
        end
      end

      context "when logged in as a random user" do
        before { fake_login }

        it "shows an error and redirects" do
          post :new, params: { tag_id: fandom.name }
          it_redirects_to_with_error(user_path(@current_user),
                                     "Sorry, you don't have permission to " \
                                     "access the page you were trying to " \
                                     "reach.")
        end
      end

      context "when logged out" do
        before { fake_logout }

        it "shows an error and redirects" do
          post :new, params: { tag_id: fandom.name }
          it_redirects_to_with_error(new_user_session_path,
                                     "Sorry, you don't have permission to " \
                                     "access the page you were trying to " \
                                     "reach. Please log in.")
        end
      end
    end

    it "renders the :new template if commentable is a valid comment" do
      comment = create(:comment)
      post :new, params: { comment_id: comment.id }
      expect(response).to render_template("new")
      expect(assigns(:name)).to eq("Previous Comment")
    end

    context "when the commentable is a work hidden by an admin" do
      let(:work) { create(:work, hidden_by_admin: true) }

      context "when logged out" do
        it "redirects to the home page with an error" do
          get :new, params: { work_id: work.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach. Please log in.")
        end
      end

      context "when logged in as a random user" do
        it "redirects to the home page with an error" do
          fake_login
          get :new, params: { work_id: work.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach.")
        end
      end

      context "when logged in as the work's owner" do
        it "redirects to the work with an error" do
          fake_login_known_user(work.users.first)
          get :new, params: { work_id: work.id }
          it_redirects_to_with_error(work_path(work), "Sorry, you can't add or edit comments on a hidden work.")
        end
      end

      context "when logged in as an admin" do
        it "redirects to the work with an error" do
          fake_login_admin(create(:admin))
          get :new, params: { work_id: work.id }
          it_redirects_to_with_error(work_path(work), "Sorry, you can't add or edit comments on a hidden work.")
        end
      end
    end

    context "when the commentable is a comment on a work hidden by an admin" do
      let(:comment) { create(:comment) }
      let(:work) { comment.ultimate_parent }

      before { work.update_column(:hidden_by_admin, true) }

      context "when logged out" do
        it "redirects to the home page with an error" do
          get :new, params: { comment_id: comment.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach. Please log in.")
        end
      end

      context "when logged in as a random user" do
        it "redirects to the home page with an error" do
          fake_login
          get :new, params: { comment_id: comment.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach.")
        end
      end

      context "when logged in as the comment writer" do
        it "redirects to the home page with an error" do
          fake_login_known_user(comment.pseud.user)
          get :new, params: { comment_id: comment.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach.")
        end
      end

      context "when logged in as the work's owner" do
        it "redirects to the work with an error" do
          fake_login_known_user(work.users.first)
          get :new, params: { comment_id: comment.id }
          it_redirects_to_with_error(work_path(work), "Sorry, you can't add or edit comments on a hidden work.")
        end
      end

      context "when logged in as an admin" do
        it "redirects to the work with an error" do
          fake_login_admin(create(:admin))
          get :new, params: { comment_id: comment.id }
          it_redirects_to_with_error(work_path(work), "Sorry, you can't add or edit comments on a hidden work.")
        end
      end
    end
  end

  describe "POST #create" do
    let(:anon_comment_attributes) do
      attributes_for(:comment).slice(:name, :email, :comment_content)
    end

    context "when replying from the inbox" do
      let!(:user) { create(:user) }
      let!(:comment) { create(:comment) }

      before do
        fake_login_known_user(user)
        request.env["HTTP_REFERER"] = user_inbox_path(user)
      end

      it "creates the reply and redirects to user inbox path" do
        comment_attributes = {
          pseud_id: user.default_pseud_id,
          comment_content: "Hello fellow human!"
        }
        post :create, params: { comment_id: comment.id, comment: comment_attributes, filters: { date: 'asc' } }
        expect(response).to redirect_to(user_inbox_path(user, filters: { date: 'asc' }))
        expect(flash[:comment_notice]).to eq "Comment created!"
      end
    end

    context "when the commentable is a valid tag" do
      let(:fandom) { create(:fandom) }

      context "when logged in as an admin" do
        before { fake_login_admin(create(:admin)) }

        it "posts the comment and shows it in context" do
          post :create, params: { tag_id: fandom.name, comment: anon_comment_attributes }
          comment = Comment.last
          expect(comment.commentable).to eq fandom
          expect(comment.name).to eq anon_comment_attributes[:name]
          expect(comment.email).to eq anon_comment_attributes[:email]
          expect(comment.comment_content).to include anon_comment_attributes[:comment_content]
          path = comments_path(tag_id: fandom.to_param,
                               anchor: "comment_#{comment.id}")
          expect(response).to redirect_to path
        end
      end

      context "when logged in as a tag wrangler" do
        before do
          fake_login
          @current_user.roles << Role.new(name: 'tag_wrangler')
        end

        it "posts the comment and shows it in context" do
          post :create, params: { tag_id: fandom.name, comment: anon_comment_attributes }
          comment = Comment.last
          expect(comment.commentable).to eq fandom
          expect(comment.name).to eq anon_comment_attributes[:name]
          expect(comment.email).to eq anon_comment_attributes[:email]
          expect(comment.comment_content).to include anon_comment_attributes[:comment_content]
          path = comments_path(tag_id: fandom.to_param,
                               anchor: "comment_#{comment.id}")
          expect(response).to redirect_to path
        end
      end

      context "when logged in as a random user" do
        before { fake_login }

        it "shows an error and redirects" do
          post :create, params: { tag_id: fandom.name, comment: anon_comment_attributes }
          it_redirects_to_with_error(user_path(@current_user),
                                     "Sorry, you don't have permission to " \
                                     "access the page you were trying to " \
                                     "reach.")
        end
      end

      context "when logged out" do
        before { fake_logout }

        it "shows an error and redirects" do
          post :create, params: { tag_id: fandom.name, comment: anon_comment_attributes }
          it_redirects_to_with_error(new_user_session_path,
                                     "Sorry, you don't have permission to " \
                                     "access the page you were trying to " \
                                     "reach. Please log in.")
        end
      end
    end

    context "when the commentable is a work hidden by an admin" do
      let(:work) { create(:work, hidden_by_admin: true) }

      context "when logged out" do
        it "redirects to the home page with an error" do
          post :create, params: { work_id: work.id, comment: anon_comment_attributes }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach. Please log in.")
        end
      end

      context "when logged in as a random user" do
        it "redirects to the home page with an error" do
          fake_login
          post :create, params: { work_id: work.id, comment: anon_comment_attributes }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach.")
        end
      end

      context "when logged in as the work's owner" do
        it "redirects to the work with an error" do
          fake_login_known_user(work.users.first)
          post :create, params: { work_id: work.id, comment: anon_comment_attributes }
          it_redirects_to_with_error(work_path(work), "Sorry, you can't add or edit comments on a hidden work.")
        end
      end

      context "when logged in as an admin" do
        it "redirects to the work with an error" do
          fake_login_admin(create(:admin))
          post :create, params: { work_id: work.id, comment: anon_comment_attributes }
          it_redirects_to_with_error(work_path(work), "Sorry, you can't add or edit comments on a hidden work.")
        end
      end
    end

    context "when the commentable is a comment on a work hidden by an admin" do
      let(:comment) { create(:comment) }
      let(:work) { comment.ultimate_parent }

      before { work.update_column(:hidden_by_admin, true) }

      context "when logged out" do
        it "redirects to the home page with an error" do
          post :create, params: { comment_id: comment.id, comment: anon_comment_attributes }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach. Please log in.")
        end
      end

      context "when logged in as a random user" do
        it "redirects to the home page with an error" do
          fake_login
          post :create, params: { comment_id: comment.id, comment: anon_comment_attributes }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach.")
        end
      end

      context "when logged in as the comment writer" do
        it "redirects to the home page with an error" do
          fake_login_known_user(comment.pseud.user)
          post :create, params: { comment_id: comment.id, comment: anon_comment_attributes }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach.")
        end
      end

      context "when logged in as the work's owner" do
        it "redirects to the work with an error" do
          fake_login_known_user(work.users.first)
          post :create, params: { comment_id: comment.id, comment: anon_comment_attributes }
          it_redirects_to_with_error(work_path(work), "Sorry, you can't add or edit comments on a hidden work.")
        end
      end

      context "when logged in as an admin" do
        it "redirects to the work with an error" do
          fake_login_admin(create(:admin))
          post :create, params: { comment_id: comment.id, comment: anon_comment_attributes }
          it_redirects_to_with_error(work_path(work), "Sorry, you can't add or edit comments on a hidden work.")
        end
      end
    end
  end

  describe "PUT #review_all" do
    xit "redirects to root path with an error if current user does not own the commentable" do
      fake_login
      put :review_all, params: { work_id: unreviewed_comment.commentable_id }
      it_redirects_to_with_error(root_path, "What did you want to review comments on?")
    end
  end

  describe "PUT #approve" do
    before { comment.update_column(:approved, false) }

    context "when logged-in as admin" do
      before { fake_login_admin(create(:admin)) }

      it "marks the comment as not spam" do
        put :approve, params: { id: comment.id }
        expect(flash[:error]).to be_nil
        expect(response).to redirect_to(work_path(comment.ultimate_parent,
                                                  show_comments: true,
                                                  anchor: 'comments'))
        expect(comment.reload.approved).to be_truthy
      end
    end

    context "when logged-in as the work's creator" do
      before { fake_login_known_user(comment.ultimate_parent.users.first) }

      it "marks the comment as not spam" do
        put :approve, params: { id: comment.id }
        expect(flash[:error]).to be_nil
        expect(response).to redirect_to(work_path(comment.ultimate_parent,
                                                  show_comments: true,
                                                  anchor: 'comments'))
        expect(comment.reload.approved).to be_truthy
      end
    end

    context "when logged-in as the comment writer" do
      before { fake_login_known_user(comment.pseud.user) }

      it "leaves the comment marked as spam and redirects with an error" do
        put :approve, params: { id: comment.id }
        expect(comment.reload.approved).to be_falsey
        it_redirects_to_with_error(
          root_path,
          "Sorry, you don't have permission to moderate that comment."
        )
      end
    end

    context "when logged-in as a random user" do
      before { fake_login }

      it "leaves the comment marked as spam and redirects with an error" do
        put :approve, params: { id: comment.id }
        expect(comment.reload.approved).to be_falsey
        it_redirects_to_with_error(
          root_path,
          "Sorry, you don't have permission to moderate that comment."
        )
      end
    end

    context "when not logged-in" do
      before { fake_logout }

      it "leaves the comment marked as spam and redirects with an error" do
        put :approve, params: { id: comment.id }
        expect(comment.reload.approved).to be_falsey
        it_redirects_to_with_error(
          login_path,
          "Sorry, you don't have permission to moderate that comment."
        )
      end
    end
  end

  describe "PUT #reject" do
    context "when logged-in as admin" do
      before { fake_login_admin(create(:admin)) }

      it "marks the comment as spam" do
        put :reject, params: { id: comment.id }
        expect(flash[:error]).to be_nil
        expect(response).to redirect_to(work_path(comment.ultimate_parent,
                                                  show_comments: true,
                                                  anchor: 'comments'))
        expect(comment.reload.approved).to be_falsey
      end
    end

    context "when logged-in as the work's creator" do
      before { fake_login_known_user(comment.ultimate_parent.users.first) }

      it "marks the comment as spam" do
        put :reject, params: { id: comment.id }
        expect(flash[:error]).to be_nil
        expect(response).to redirect_to(work_path(comment.ultimate_parent,
                                                  show_comments: true,
                                                  anchor: 'comments'))
        expect(comment.reload.approved).to be_falsey
      end
    end

    context "when logged-in as the comment writer" do
      before { fake_login_known_user(comment.pseud.user) }

      it "doesn't mark the comment as spam and redirects with an error" do
        put :reject, params: { id: comment.id }
        expect(comment.reload.approved).to be_truthy
        it_redirects_to_with_error(
          root_path,
          "Sorry, you don't have permission to moderate that comment."
        )
      end
    end

    context "when logged-in as a random user" do
      before { fake_login }

      it "doesn't mark the comment as spam and redirects with an error" do
        put :reject, params: { id: comment.id }
        expect(comment.reload.approved).to be_truthy
        it_redirects_to_with_error(
          root_path,
          "Sorry, you don't have permission to moderate that comment."
        )
      end
    end

    context "when not logged-in" do
      before { fake_logout }

      it "doesn't mark the comment as spam and redirects with an error" do
        put :reject, params: { id: comment.id }
        expect(comment.reload.approved).to be_truthy
        it_redirects_to_with_error(
          login_path,
          "Sorry, you don't have permission to moderate that comment."
        )
      end
    end
  end

  describe "GET #show_comments" do
    context "when the commentable is a valid tag" do
      let(:fandom) { create(:fandom) }

      let(:all_comments_path) do
        comments_path(tag_id: fandom.to_param, anchor: "comments")
      end

      context "when logged in as an admin" do
        before { fake_login_admin(create(:admin)) }

        it "redirects to the tag comments page when the format is html" do
          get :show_comments, params: { tag_id: fandom.name }
          expect(response).to redirect_to all_comments_path
        end

        it "loads the comments when the format is javascript" do
          get :show_comments, params: { tag_id: fandom.name, format: :js }, xhr: true
          expect(response).to render_template(:show_comments)
        end
      end

      context "when logged in as a tag wrangler" do
        before do
          fake_login
          @current_user.roles << Role.new(name: 'tag_wrangler')
        end

        it "redirects to the tag comments page when the format is html" do
          get :show_comments, params: { tag_id: fandom.name }
          expect(response).to redirect_to all_comments_path
        end

        it "loads the comments when the format is javascript" do
          get :show_comments, params: { tag_id: fandom.name, format: :js }, xhr: true
          expect(response).to render_template(:show_comments)
        end
      end

      context "when logged in as a random user" do
        before { fake_login }

        it "shows an error and redirects" do
          get :show_comments, params: { tag_id: fandom.name }
          it_redirects_to_with_error(user_path(@current_user),
                                     "Sorry, you don't have permission to " \
                                     "access the page you were trying to " \
                                     "reach.")
        end
      end

      context "when logged out" do
        before { fake_logout }

        it "shows an error and redirects" do
          get :show_comments, params: { tag_id: fandom.name }
          it_redirects_to_with_error(new_user_session_path,
                                     "Sorry, you don't have permission to " \
                                     "access the page you were trying to " \
                                     "reach. Please log in.")
        end
      end
    end

    context "when the commentable is a work hidden by an admin" do
      let(:work) { create(:work, hidden_by_admin: true) }

      context "when logged out" do
        it "redirects to the home page with an error" do
          get :show_comments, params: { work_id: work.id, format: :js }, xhr: true
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach. Please log in.")
        end
      end

      context "when logged in as a random user" do
        it "redirects to the home page with an error" do
          fake_login
          get :show_comments, params: { work_id: work.id, format: :js }, xhr: true
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach.")
        end
      end

      context "when logged in as the work's owner" do
        it "renders the show_comments template" do
          fake_login_known_user(work.users.first)
          get :show_comments, params: { work_id: work.id, format: :js }, xhr: true
          expect(response).to render_template(:show_comments)
        end
      end

      context "when logged in as an admin" do
        it "renders the show_comments template" do
          fake_login_admin(create(:admin))
          get :show_comments, params: { work_id: work.id, format: :js }, xhr: true
          expect(response).to render_template(:show_comments)
        end
      end
    end
  end

  describe "GET #hide_comments" do
    it "redirects to the comment path without an error" do
      get :hide_comments, params: { comment_id: unreviewed_comment.id }
      expect(flash[:error]).to be_nil
      expect(response).to redirect_to(comment_path(unreviewed_comment, anchor: 'comments'))
    end
  end

  describe "GET #add_comment" do
    context "when comment is unreviewed" do
      it "redirects to the comment path with add_comment params and without an error" do
        get :add_comment, params: { comment_id: unreviewed_comment.id }
        expect(flash[:error]).to be_nil
        expect(response).to redirect_to(comment_path(unreviewed_comment, add_comment: true, anchor: 'comments'))
      end
    end

    context "when the commentable is a work hidden by an admin" do
      let(:work) { create(:work, hidden_by_admin: true) }

      context "when logged out" do
        it "redirects to the home page with an error" do
          get :add_comment, params: { work_id: work.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach. Please log in.")
        end
      end

      context "when logged in as a random user" do
        it "redirects to the home page with an error" do
          fake_login
          get :add_comment, params: { work_id: work.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach.")
        end
      end

      context "when logged in as the work's owner" do
        it "redirects to the work with an error" do
          fake_login_known_user(work.users.first)
          get :add_comment, params: { work_id: work.id }
          it_redirects_to_with_error(work_path(work), "Sorry, you can't add or edit comments on a hidden work.")
        end
      end

      context "when logged in as an admin" do
        it "redirects to the work with an error" do
          fake_login_admin(create(:admin))
          get :add_comment, params: { work_id: work.id }
          it_redirects_to_with_error(work_path(work), "Sorry, you can't add or edit comments on a hidden work.")
        end
      end
    end
  end

  describe "GET #cancel_comment" do
    context "with only valid params" do
      it "redirects to comment path with the comments anchor and without an error" do
        get :cancel_comment, params: { comment_id: comment.id }
        expect(flash[:error]).to be_nil
        expect(response).to redirect_to(comment_path(comment, anchor: "comments"))
      end
    end

    context "with valid and invalid params" do
      it "removes invalid params and redirects without an error to comment path with valid params and the comments anchor" do
        get :cancel_comment, params: { comment_id: comment.id, show_comments: 'yes', random_option: 'no' }
        expect(flash[:error]).to be_nil
        expect(response).to redirect_to(comment_path(comment, show_comments: 'yes', anchor: "comments"))
      end
    end
  end

  describe "GET #cancel_comment_reply" do
    context "with only valid params" do
      it "redirects to comment path with the comments anchor and without an error" do
        get :cancel_comment_reply, params: { comment_id: comment.id }
        expect(flash[:error]).to be_nil
        expect(response).to redirect_to(comment_path(comment, anchor: "comments"))
      end
    end

    context "with valid and invalid params" do
      it "removes invalid params and redirects without an error to comment path with valid params and the comments anchor" do
        get :cancel_comment_reply, params: { comment_id: comment.id, show_comments: 'yes', random_option: 'no' }
        expect(flash[:error]).to be_nil
        expect(response).to redirect_to(comment_path(comment, show_comments: 'yes', anchor: "comments"))
      end
    end
  end

  describe "GET #cancel_comment_delete" do
    it "redirects to the comment on the commentable without an error" do
      get :cancel_comment_delete, params: { id: comment.id }
      expect(flash[:error]).to be_nil
      expect(response).to redirect_to(work_path(comment.ultimate_parent, show_comments: true, anchor: "comment_#{comment.id}"))
    end
  end

  describe "GET #cancel_comment_edit" do
    context "when logged in as the comment writer" do
      before { fake_login_known_user(comment.pseud.user) }

      context "when the format is html" do
        it "redirects to the comment on the commentable without an error" do
          get :cancel_comment_edit, params: { id: comment.id }
          expect(flash[:error]).to be_nil
          expect(response).to redirect_to(work_path(comment.ultimate_parent, show_comments: true, anchor: "comment_#{comment.id}"))
        end
      end

      context "when the format is javascript" do
        it "loads the javascript to restore the comment" do
          get :cancel_comment_edit, params: { id: comment.id, format: :js }, xhr: true
          expect(response).to render_template("cancel_comment_edit")
        end
      end
    end

    context "when logged in as a random user" do
      before { fake_login }

      it "shows an error and redirects" do
        get :cancel_comment_edit, params: { id: comment.id }
        it_redirects_to_with_error(comment,
                                   "Sorry, you don't have permission to " \
                                   "access the page you were trying to " \
                                   "reach.")
      end
    end

    context "when logged out" do
      before { fake_logout }

      it "shows an error and redirects" do
        get :cancel_comment_edit, params: { id: comment.id }
        it_redirects_to_with_error(comment,
                                   "Sorry, you don't have permission to " \
                                   "access the page you were trying to " \
                                   "reach. Please log in.")
      end
    end
  end

  describe "GET #destroy" do
    context "when logged in as the owner of the unreviewed comment" do
      it "deletes the comment and redirects to referrer with a success message" do
        fake_login
        comment = create(:unreviewed_comment, pseud_id: @current_user.default_pseud.id)
        get :destroy, params: { id: comment.id }
        expect(Comment.find_by(id: comment.id)).to_not be_present
        expect(response).to redirect_to("/where_i_came_from")
        expect(flash[:notice]).to eq "Comment deleted."
      end
      it "redirects and gives an error if the comment could not be deleted" do
        fake_login
        comment = create(:unreviewed_comment, pseud_id: @current_user.default_pseud.id)
        allow_any_instance_of(Comment).to receive(:destroy_or_mark_deleted).and_return(false)
        get :destroy, params: { id: comment.id }
        allow_any_instance_of(Comment).to receive(:destroy_or_mark_deleted).and_call_original
        expect(Comment.find_by(id: comment.id)).to be_present
        expect(response).to redirect_to(work_path(comment.ultimate_parent, show_comments: true, anchor: "comment_#{comment.id}"))
        expect(flash[:comment_error]).to eq "We couldn't delete that comment."
      end
    end

    context "when the comment is on a work hidden by an admin" do
      let(:work) { comment.ultimate_parent }

      before { work.update_column(:hidden_by_admin, true) }

      context "when logged out" do
        it "redirects to the home page with an error" do
          delete :destroy, params: { id: comment.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach. Please log in.")
        end
      end

      context "when logged in as a random user" do
        it "redirects to the home page with an error" do
          fake_login
          delete :destroy, params: { id: comment.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach.")
        end
      end

      context "when logged in as the comment writer" do
        it "redirects to the home page with an error" do
          fake_login_known_user(comment.pseud.user)
          delete :destroy, params: { id: comment.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach.")
        end
      end

      context "when logged in as the work's owner" do
        it "successfully deletes the comment" do
          fake_login_known_user(work.users.first)
          delete :destroy, params: { id: comment.id }
          expect(flash[:comment_notice]).to eq "Comment deleted."
          it_redirects_to_simple(work_path(work, show_comments: true, anchor: :comments))
          expect { comment.reload }.to raise_exception(ActiveRecord::RecordNotFound)
        end
      end

      context "when logged in as an admin" do
        it "successfully deletes the comment" do
          fake_login_admin(create(:admin))
          delete :destroy, params: { id: comment.id }
          expect(flash[:comment_notice]).to eq "Comment deleted."
          it_redirects_to_simple(work_path(work, show_comments: true, anchor: :comments))
          expect { comment.reload }.to raise_exception(ActiveRecord::RecordNotFound)
        end
      end
    end
  end

  describe "PUT #review" do
    let!(:user) { create(:user) }
    let!(:work) { create(:work, authors: [user.default_pseud], moderated_commenting_enabled: true ) }
    let(:comment) { create(:unreviewed_comment, commentable_id: work.id) }

    before do
      fake_login_known_user(user)
    end

    context "when recipient approves comment from inbox" do
      it "marks comment reviewed and redirects to user inbox path with success message" do
        put :review, params: { id: comment.id, approved_from: "inbox" }
        expect(response).to redirect_to(user_inbox_path(user))
        expect(flash[:notice]).to eq "Comment approved."
        comment.reload
        expect(comment.unreviewed).to be false
      end
    end

    context "when recipient approves comment from inbox with filters" do
      it "marks comment reviewed and redirects to user inbox path with success message" do
        put :review, params: { id: comment.id, approved_from: "inbox", filters: { date: 'asc' } }
        expect(response).to redirect_to(user_inbox_path(user, filters: { date: 'asc' }))
        expect(flash[:notice]).to eq "Comment approved."
        comment.reload
        expect(comment.unreviewed).to be false
      end
    end

    context "when recipient approves comment from homepage" do
      it "marks comment reviewed and redirects to root path with success message" do
        put :review, params: { id: comment.id, approved_from: "home" }
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq "Comment approved."
        comment.reload
        expect(comment.unreviewed).to be false
      end
    end
  end

  describe "GET #show" do
    it "redirects to root path if logged in user does not have permission to access comment" do
      fake_login
      get :show, params: { id: unreviewed_comment.id }
      it_redirects_to_with_error(root_path, "Sorry, that comment is currently in moderation.")
    end

    context "when the comment is on a work hidden by an admin" do
      let(:work) { comment.ultimate_parent }

      before { work.update_column(:hidden_by_admin, true) }

      context "when logged out" do
        it "redirects to the home page with an error" do
          get :show, params: { id: comment.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach. Please log in.")
        end
      end

      context "when logged in as a random user" do
        it "redirects to the home page with an error" do
          fake_login
          get :show, params: { id: comment.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach.")
        end
      end

      context "when logged in as the comment writer" do
        it "redirects to the home page with an error" do
          fake_login_known_user(comment.pseud.user)
          get :show, params: { id: comment.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach.")
        end
      end

      context "when logged in as the work's owner" do
        it "successfully displays the comment" do
          fake_login_known_user(work.users.first)
          get :show, params: { id: comment.id }
          expect(response).to render_template(:show)
          expect(assigns[:comment]).to eq(comment)
        end
      end

      context "when logged in as an admin" do
        it "successfully displays the comment" do
          fake_login_admin(create(:admin))
          get :show, params: { id: comment.id }
          expect(response).to render_template(:show)
          expect(assigns[:comment]).to eq(comment)
        end
      end
    end
  end

  describe "GET #index" do
    it "errors when not logged in as admin" do
      get :index
      expect(flash[:error]).to eq "Sorry, you don't have permission to access that page."
    end

    it "renders :index template when logged in as admin" do
      fake_login_admin(create(:admin))
      get :index
      expect(response).to render_template("index")
    end

    context "when the commentable is a work hidden by an admin" do
      let(:work) { create(:work, hidden_by_admin: true) }

      context "when logged out" do
        it "redirects to the home page with an error" do
          get :index, params: { work_id: work.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach. Please log in.")
        end
      end

      context "when logged in as a random user" do
        it "redirects to the home page with an error" do
          fake_login
          get :index, params: { work_id: work.id }
          it_redirects_to_with_error(root_path, "Sorry, you don't have permission to access the page you were trying to reach.")
        end
      end

      context "when logged in as the work's owner" do
        it "renders the index template" do
          fake_login_known_user(work.users.first)
          get :index, params: { work_id: work.id }
          expect(response).to render_template(:index)
        end
      end

      context "when logged in as an admin" do
        it "renders the index template" do
          fake_login_admin(create(:admin))
          get :index, params: { work_id: work.id }
          expect(response).to render_template(:index)
        end
      end
    end
  end
end
