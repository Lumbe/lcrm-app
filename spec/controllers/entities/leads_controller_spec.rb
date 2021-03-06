# Copyright (c) 2008-2013 Michael Dvorkin and contributors.
#
# Fat Free CRM is freely distributable under the terms of MIT license.
# See MIT-LICENSE file or http://www.opensource.org/licenses/mit-license.php
#------------------------------------------------------------------------------
require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe LeadsController do
  before(:each) do
    require_user
    set_current_tab(:leads)
  end

  # GET /leads
  # GET /leads.xml                                                AJAX and HTML
  #----------------------------------------------------------------------------
  describe "responding to GET index" do
    it "should expose all leads as @leads and render [index] template" do
      @leads = [FactoryGirl.create(:lead, user: current_user)]

      get :index
      expect(assigns[:leads]).to eq(@leads)
      expect(response).to render_template("leads/index")
    end

    it "should collect the data for the leads sidebar" do
      @leads = [FactoryGirl.create(:lead, user: current_user)]
      @status = Setting.lead_status.dup

      get :index
      expect(assigns[:lead_status_total].keys.map(&:to_sym) - (@status << :all << :other)).to eq([])
    end

    it "should filter out leads by status" do
      controller.session[:leads_filter] = "new,contacted"
      @leads = [
        FactoryGirl.create(:lead, status: "new", user: current_user),
        FactoryGirl.create(:lead, status: "contacted", user: current_user)
      ]

      # This one should be filtered out.
      FactoryGirl.create(:lead, status: "rejected", user: current_user)

      get :index
      # Note: can't compare campaigns directly because of BigDecimals.
      expect(assigns[:leads].size).to eq(2)
      expect(assigns[:leads].map(&:status).sort).to eq(%w(contacted new))
    end

    it "should perform lookup using query string" do
      @billy_bones   = FactoryGirl.create(:lead, user: current_user, first_name: "Billy",   last_name: "Bones")
      @captain_flint = FactoryGirl.create(:lead, user: current_user, first_name: "Captain", last_name: "Flint")

      get :index, query: "bill"
      expect(assigns[:leads]).to eq([@billy_bones])
      expect(assigns[:current_query]).to eq("bill")
      expect(session[:leads_current_query]).to eq("bill")
    end

    describe "AJAX pagination" do
      it "should pick up page number from params" do
        @leads = [FactoryGirl.create(:lead, user: current_user)]
        xhr :get, :index, page: 42

        expect(assigns[:current_page].to_i).to eq(42)
        expect(assigns[:leads]).to eq([]) # page #42 should be empty if there's only one lead ;-)
        expect(session[:leads_current_page].to_i).to eq(42)
        expect(response).to render_template("leads/index")
      end

      it "should pick up saved page number from session" do
        session[:leads_current_page] = 42
        session[:leads_current_query] = "bill"
        @leads = [FactoryGirl.create(:lead, user: current_user)]
        xhr :get, :index, query: "bill"

        expect(assigns[:current_page]).to eq(42)
        expect(assigns[:leads]).to eq([])
        expect(response).to render_template("leads/index")
      end

      it "should reset current_page when query is altered" do
        session[:leads_current_page] = 42
        session[:leads_current_query] = "bill"
        @leads = [FactoryGirl.create(:lead, user: current_user)]
        xhr :get, :index

        expect(assigns[:current_page]).to eq(1)
        expect(assigns[:leads]).to eq(@leads)
        expect(response).to render_template("leads/index")
      end
    end

    describe "with mime type of JSON" do
      it "should render all leads as JSON" do
        expect(@controller).to receive(:get_leads).and_return(leads = double("Array of Leads"))
        expect(leads).to receive(:to_json).and_return("generated JSON")

        request.env["HTTP_ACCEPT"] = "application/json"
        get :index
        expect(response.body).to eq("generated JSON")
      end
    end

    describe "with mime type of XML" do
      it "should render all leads as xml" do
        expect(@controller).to receive(:get_leads).and_return(leads = double("Array of Leads"))
        expect(leads).to receive(:to_xml).and_return("generated XML")

        request.env["HTTP_ACCEPT"] = "application/xml"
        get :index
        expect(response.body).to eq("generated XML")
      end
    end
  end

  # GET /leads/1
  # GET /leads/1.xml                                                       HTML
  #----------------------------------------------------------------------------
  describe "responding to GET show" do
    describe "with mime type of HTML" do
      before(:each) do
        @lead = FactoryGirl.create(:lead, id: 42, user: current_user)
        @comment = Comment.new
      end

      it "should expose the requested lead as @lead and render [show] template" do
        get :show, id: 42
        expect(assigns[:lead]).to eq(@lead)
        expect(assigns[:comment].attributes).to eq(@comment.attributes)
        expect(response).to render_template("leads/show")
      end

      it "should update an activity when viewing the lead" do
        get :show, id: @lead.id
        expect(@lead.versions.last.event).to eq('view')
      end
    end

    describe "with mime type of JSON" do
      it "should render the requested lead as JSON" do
        @lead = FactoryGirl.create(:lead, id: 42, user: current_user)
        expect(Lead).to receive(:find).and_return(@lead)
        expect(@lead).to receive(:to_json).and_return("generated JSON")

        request.env["HTTP_ACCEPT"] = "application/json"
        get :show, id: 42
        expect(response.body).to eq("generated JSON")
      end
    end

    describe "with mime type of XML" do
      it "should render the requested lead as xml" do
        @lead = FactoryGirl.create(:lead, id: 42, user: current_user)
        expect(Lead).to receive(:find).and_return(@lead)
        expect(@lead).to receive(:to_xml).and_return("generated XML")

        request.env["HTTP_ACCEPT"] = "application/xml"
        get :show, id: 42
        expect(response.body).to eq("generated XML")
      end
    end

    describe "lead got deleted or otherwise unavailable" do
      it "should redirect to lead index if the lead got deleted" do
        @lead = FactoryGirl.create(:lead, user: current_user)
        @lead.destroy

        get :show, id: @lead.id
        expect(flash[:warning]).not_to eq(nil)
        expect(response).to redirect_to(leads_path)
      end

      it "should redirect to lead index if the lead is protected" do
        @private = FactoryGirl.create(:lead, user: FactoryGirl.create(:user), access: "Private")

        get :show, id: @private.id
        expect(flash[:warning]).not_to eq(nil)
        expect(response).to redirect_to(leads_path)
      end

      it "should return 404 (Not Found) JSON error" do
        @lead = FactoryGirl.create(:lead, user: current_user)
        @lead.destroy
        request.env["HTTP_ACCEPT"] = "application/json"

        get :show, id: @lead.id
        expect(response.code).to eq("404") # :not_found
      end

      it "should return 404 (Not Found) XML error" do
        @lead = FactoryGirl.create(:lead, user: current_user)
        @lead.destroy
        request.env["HTTP_ACCEPT"] = "application/xml"

        get :show, id: @lead.id
        expect(response.code).to eq("404") # :not_found
      end
    end
  end

  # GET /leads/new
  # GET /leads/new.xml                                                     AJAX
  #----------------------------------------------------------------------------
  describe "responding to GET new" do
    it "should expose a new lead as @lead and render [new] template" do
      @lead = FactoryGirl.build(:lead, user: current_user, campaign: nil)
      allow(Lead).to receive(:new).and_return(@lead)
      @campaigns = [FactoryGirl.create(:campaign, user: current_user)]

      xhr :get, :new
      expect(assigns[:lead].attributes).to eq(@lead.attributes)
      expect(assigns[:campaigns]).to eq(@campaigns)
      expect(response).to render_template("leads/new")
    end

    it "should create related object when necessary" do
      @campaign = FactoryGirl.create(:campaign, id: 123)

      xhr :get, :new, related: "campaign_123"
      expect(assigns[:campaign]).to eq(@campaign)
    end

    describe "(when creating related lead)" do
      it "should redirect to parent asset's index page with the message if parent asset got deleted" do
        @campaign = FactoryGirl.create(:campaign)
        @campaign.destroy

        xhr :get, :new, related: "campaign_#{@campaign.id}"
        expect(flash[:warning]).not_to eq(nil)
        expect(response.body).to eq('window.location.href = "/campaigns";')
      end

      it "should redirect to parent asset's index page with the message if parent asset got protected" do
        @campaign = FactoryGirl.create(:campaign, access: "Private")

        xhr :get, :new, related: "campaign_#{@campaign.id}"
        expect(flash[:warning]).not_to eq(nil)
        expect(response.body).to eq('window.location.href = "/campaigns";')
      end
    end
  end

  # GET /leads/1/edit                                                      AJAX
  #----------------------------------------------------------------------------
  describe "responding to GET edit" do
    it "should expose the requested lead as @lead and render [edit] template" do
      @lead = FactoryGirl.create(:lead, id: 42, user: current_user, campaign: nil)
      @campaigns = [FactoryGirl.create(:campaign, user: current_user)]

      xhr :get, :edit, id: 42
      expect(assigns[:lead]).to eq(@lead)
      expect(assigns[:campaigns]).to eq(@campaigns)
      expect(response).to render_template("leads/edit")
    end

    it "should find previous lead when necessary" do
      @lead = FactoryGirl.create(:lead, id: 42)
      @previous = FactoryGirl.create(:lead, id: 321)

      xhr :get, :edit, id: 42, previous: 321
      expect(assigns[:previous]).to eq(@previous)
    end

    describe "lead got deleted or is otherwise unavailable" do
      it "should reload current page with the flash message if the lead got deleted" do
        @lead = FactoryGirl.create(:lead, user: current_user)
        @lead.destroy

        xhr :get, :edit, id: @lead.id
        expect(flash[:warning]).not_to eq(nil)
        expect(response.body).to eq("window.location.reload();")
      end

      it "should reload current page with the flash message if the lead is protected" do
        @private = FactoryGirl.create(:lead, user: FactoryGirl.create(:user), access: "Private")

        xhr :get, :edit, id: @private.id
        expect(flash[:warning]).not_to eq(nil)
        expect(response.body).to eq("window.location.reload();")
      end
    end

    describe "(previous lead got deleted or is otherwise unavailable)" do
      before(:each) do
        @lead = FactoryGirl.create(:lead, user: current_user)
        @previous = FactoryGirl.create(:lead, user: FactoryGirl.create(:user))
      end

      it "should notify the view if previous lead got deleted" do
        @previous.destroy

        xhr :get, :edit, id: @lead.id, previous: @previous.id
        expect(flash[:warning]).to eq(nil) # no warning, just silently remove the div
        expect(assigns[:previous]).to eq(@previous.id)
        expect(response).to render_template("leads/edit")
      end

      it "should notify the view if previous lead got protected" do
        @previous.update_attribute(:access, "Private")

        xhr :get, :edit, id: @lead.id, previous: @previous.id
        expect(flash[:warning]).to eq(nil)
        expect(assigns[:previous]).to eq(@previous.id)
        expect(response).to render_template("leads/edit")
      end
    end
  end

  # POST /leads
  # POST /leads.xml                                                        AJAX
  #----------------------------------------------------------------------------
  describe "responding to POST create" do
    describe "with valid params" do
      it "should expose a newly created lead as @lead and render [create] template" do
        @lead = FactoryGirl.build(:lead, user: current_user, campaign: nil)
        allow(Lead).to receive(:new).and_return(@lead)
        @campaigns = [FactoryGirl.create(:campaign, user: current_user)]

        xhr :post, :create, lead: { first_name: "Billy", last_name: "Bones" }
        expect(assigns(:lead)).to eq(@lead)
        expect(assigns(:campaigns)).to eq(@campaigns)
        expect(assigns[:lead_status_total]).to be_nil
        expect(response).to render_template("leads/create")
      end

      it "should copy selected campaign permissions unless asked otherwise" do
        he  = FactoryGirl.create(:user, id: 7)
        she = FactoryGirl.create(:user, id: 8)
        @campaign = FactoryGirl.build(:campaign, access: "Shared")
        @campaign.permissions << FactoryGirl.build(:permission, user: he,  asset: @campaign)
        @campaign.permissions << FactoryGirl.build(:permission, user: she, asset: @campaign)
        @campaign.save

        @lead = FactoryGirl.build(:lead, campaign: @campaign, user: current_user, access: "Shared")
        allow(Lead).to receive(:new).and_return(@lead)

        xhr :post, :create, lead: { first_name: "Billy", last_name: "Bones", access: "Campaign", user_ids: %w(7 8) }, campaign: @campaign.id
        expect(assigns(:lead)).to eq(@lead)
        expect(@lead.reload.access).to eq("Shared")
        expect(@lead.permissions.map(&:user_id).sort).to eq([7, 8])
        expect(@lead.permissions.map(&:asset_id)).to eq([@lead.id, @lead.id])
        expect(@lead.permissions.map(&:asset_type)).to eq(%w(Lead Lead))
      end

      it "should get the data to update leads sidebar if called from leads index" do
        @lead = FactoryGirl.build(:lead, user: current_user, campaign: nil)
        allow(Lead).to receive(:new).and_return(@lead)

        request.env["HTTP_REFERER"] = "http://localhost/leads"
        xhr :post, :create, lead: { first_name: "Billy", last_name: "Bones" }
        expect(assigns[:lead_status_total]).to be_an_instance_of(HashWithIndifferentAccess)
      end

      it "should reload leads to update pagination if called from leads index" do
        @lead = FactoryGirl.build(:lead, user: current_user, campaign: nil)
        allow(Lead).to receive(:new).and_return(@lead)

        request.env["HTTP_REFERER"] = "http://localhost/leads"
        xhr :post, :create, lead: { first_name: "Billy", last_name: "Bones" }
        expect(assigns[:leads]).to eq([@lead])
      end

      it "should reload lead campaign if called from campaign landing page" do
        @campaign = FactoryGirl.create(:campaign)
        @lead = FactoryGirl.build(:lead, user: current_user, campaign: @campaign)

        request.env["HTTP_REFERER"] = "http://localhost/campaigns/#{@campaign.id}"
        xhr :put, :create, lead: { first_name: "Billy", last_name: "Bones" }, campaign: @campaign.id
        expect(assigns[:campaign]).to eq(@campaign)
      end

      it "should add a new comment to the newly created lead when specified" do
        @lead = FactoryGirl.create(:lead)
        allow(Lead).to receive(:new).and_return(@lead)
        xhr :post, :create, lead: { first_name: "Test", last_name: "Lead" }, comment_body: "This is an important lead."
        expect(@lead.reload.comments.map(&:comment)).to include("This is an important lead.")
      end
    end

    describe "with invalid params" do
      it "should expose a newly created but unsaved lead as @lead and still render [create] template" do
        @lead = FactoryGirl.build(:lead, user: current_user, first_name: nil, campaign: nil)
        allow(Lead).to receive(:new).and_return(@lead)
        @campaigns = [FactoryGirl.create(:campaign, user: current_user)]

        xhr :post, :create, lead: { first_name: nil }
        expect(assigns(:lead)).to eq(@lead)
        expect(assigns(:campaigns)).to eq(@campaigns)
        expect(assigns[:lead_status_total]).to eq(nil)
        expect(response).to render_template("leads/create")
      end
    end
  end

  # PUT /leads/1
  # PUT /leads/1.xml
  #----------------------------------------------------------------------------
  describe "responding to PUT update" do
    describe "with valid params" do
      it "should update the requested lead, expose it as @lead, and render [update] template" do
        @lead = FactoryGirl.create(:lead, first_name: "Billy", user: current_user)

        xhr :put, :update, id: @lead.id, lead: { first_name: "Bones" }
        expect(@lead.reload.first_name).to eq("Bones")
        expect(assigns[:lead]).to eq(@lead)
        expect(assigns[:lead_status_total]).to eq(nil)
        expect(response).to render_template("leads/update")
      end

      it "should update lead status" do
        @lead = FactoryGirl.create(:lead, status: "new", user: current_user)

        xhr :put, :update, id: @lead.id, lead: { status: "rejected" }
        expect(@lead.reload.status).to eq("rejected")
      end

      it "should update lead source" do
        @lead = FactoryGirl.create(:lead, source: "campaign", user: current_user)

        xhr :put, :update, id: @lead.id, lead: { source: "cald_call" }
        expect(@lead.reload.source).to eq("cald_call")
      end

      it "should update lead campaign" do
        @campaigns = { old: FactoryGirl.create(:campaign), new: FactoryGirl.create(:campaign) }
        @lead = FactoryGirl.create(:lead, campaign: @campaigns[:old])

        xhr :put, :update, id: @lead.id, lead: { campaign_id: @campaigns[:new].id }
        expect(@lead.reload.campaign).to eq(@campaigns[:new])
      end

      it "should decrement campaign leads count if campaign has been removed" do
        @campaign = FactoryGirl.create(:campaign)
        @lead = FactoryGirl.create(:lead, campaign: @campaign)
        @count = @campaign.reload.leads_count

        xhr :put, :update, id: @lead, lead: { campaign_id: nil }
        expect(@lead.reload.campaign).to eq(nil)
        expect(@campaign.reload.leads_count).to eq(@count - 1)
      end

      it "should increment campaign leads count if campaign has been assigned" do
        @campaign = FactoryGirl.create(:campaign)
        @lead = FactoryGirl.create(:lead, campaign: nil)
        @count = @campaign.leads_count

        xhr :put, :update, id: @lead, lead: { campaign_id: @campaign.id }
        expect(@lead.reload.campaign).to eq(@campaign)
        expect(@campaign.reload.leads_count).to eq(@count + 1)
      end

      it "should update both campaign leads counts if reassigned to a new campaign" do
        @campaigns = { old: FactoryGirl.create(:campaign), new: FactoryGirl.create(:campaign) }
        @lead = FactoryGirl.create(:lead, campaign: @campaigns[:old])
        @counts = { old: @campaigns[:old].reload.leads_count, new: @campaigns[:new].leads_count }

        xhr :put, :update, id: @lead, lead: { campaign_id: @campaigns[:new].id }
        expect(@lead.reload.campaign).to eq(@campaigns[:new])
        expect(@campaigns[:old].reload.leads_count).to eq(@counts[:old] - 1)
        expect(@campaigns[:new].reload.leads_count).to eq(@counts[:new] + 1)
      end

      it "should update shared permissions for the lead" do
        @lead = FactoryGirl.create(:lead, user: current_user)
        he  = FactoryGirl.create(:user, id: 7)
        she = FactoryGirl.create(:user, id: 8)

        xhr :put, :update, id: @lead.id, lead: { access: "Shared", user_ids: %w(7 8) }
        expect(@lead.user_ids.sort).to eq([7, 8])
      end

      it "should get the data for leads sidebar when called from leads index" do
        @lead = FactoryGirl.create(:lead)

        request.env["HTTP_REFERER"] = "http://localhost/leads"
        xhr :put, :update, id: @lead.id, lead: { first_name: "Billy" }
        expect(assigns[:lead_status_total]).not_to be_nil
        expect(assigns[:lead_status_total]).to be_an_instance_of(HashWithIndifferentAccess)
      end

      it "should reload lead campaign if called from campaign landing page" do
        @campaign = FactoryGirl.create(:campaign)
        @lead = FactoryGirl.create(:lead, campaign: @campaign)

        request.env["HTTP_REFERER"] = "http://localhost/campaigns/#{@campaign.id}"
        xhr :put, :update, id: @lead.id, lead: { first_name: "Hello" }
        expect(assigns[:campaign]).to eq(@campaign)
      end

      describe "lead got deleted or otherwise unavailable" do
        it "should reload current page with the flash message if the lead got deleted" do
          @lead = FactoryGirl.create(:lead, user: current_user)
          @lead.destroy

          xhr :put, :update, id: @lead.id
          expect(flash[:warning]).not_to eq(nil)
          expect(response.body).to eq("window.location.reload();")
        end

        it "should reload current page with the flash message if the lead is protected" do
          @private = FactoryGirl.create(:lead, user: FactoryGirl.create(:user), access: "Private")

          xhr :put, :update, id: @private.id
          expect(flash[:warning]).not_to eq(nil)
          expect(response.body).to eq("window.location.reload();")
        end
      end
    end

    describe "with invalid params" do
      it "should not update the lead, but still expose it as @lead and render [update] template" do
        @lead = FactoryGirl.create(:lead, id: 42, user: current_user, campaign: nil)
        @campaigns = [FactoryGirl.create(:campaign, user: current_user)]

        xhr :put, :update, id: 42, lead: { first_name: nil }
        expect(assigns[:lead]).to eq(@lead)
        expect(assigns[:campaigns]).to eq(@campaigns)
        expect(response).to render_template("leads/update")
      end
    end
  end

  # DELETE /leads/1
  # DELETE /leads/1.xml                                           AJAX and HTML
  #----------------------------------------------------------------------------
  describe "responding to DELETE destroy" do
    before(:each) do
      @lead = FactoryGirl.create(:lead, user: current_user)
    end

    describe "AJAX request" do
      it "should destroy the requested lead and render [destroy] template" do
        xhr :delete, :destroy, id: @lead.id

        expect(assigns[:leads]).to eq(nil) # @lead got deleted
        expect { Lead.find(@lead.id) }.to raise_error(ActiveRecord::RecordNotFound)
        expect(response).to render_template("leads/destroy")
      end

      describe "when called from Leads index page" do
        before(:each) do
          request.env["HTTP_REFERER"] = "http://localhost/leads"
        end

        it "should get data for the sidebar" do
          @another_lead = FactoryGirl.create(:lead, user: current_user)

          xhr :delete, :destroy, id: @lead.id
          expect(assigns[:leads]).to eq([@another_lead]) # @lead got deleted
          expect(assigns[:lead_status_total]).not_to be_nil
          expect(assigns[:lead_status_total]).to be_an_instance_of(HashWithIndifferentAccess)
          expect(response).to render_template("leads/destroy")
        end

        it "should try previous page and render index action if current page has no leads" do
          session[:leads_current_page] = 42

          xhr :delete, :destroy, id: @lead.id
          expect(session[:leads_current_page]).to eq(41)
          expect(response).to render_template("leads/index")
        end

        it "should render index action when deleting last lead" do
          session[:leads_current_page] = 1

          xhr :delete, :destroy, id: @lead.id
          expect(session[:leads_current_page]).to eq(1)
          expect(response).to render_template("leads/index")
        end
      end

      describe "when called from campaign landing page" do
        before(:each) do
          @campaign = FactoryGirl.create(:campaign)
          @lead = FactoryGirl.create(:lead, user: current_user, campaign: @campaign)
          request.env["HTTP_REFERER"] = "http://localhost/campaigns/#{@campaign.id}"
        end

        it "should reset current page to 1" do
          xhr :delete, :destroy, id: @lead.id
          expect(session[:leads_current_page]).to eq(1)
          expect(response).to render_template("leads/destroy")
        end

        it "should reload campaiign to be able to refresh its summary" do
          xhr :delete, :destroy, id: @lead.id
          expect(assigns[:campaign]).to eq(@campaign)
          expect(response).to render_template("leads/destroy")
        end
      end

      describe "lead got deleted or otherwise unavailable" do
        it "should reload current page with the flash message if the lead got deleted" do
          @lead = FactoryGirl.create(:lead, user: current_user)
          @lead.destroy

          xhr :delete, :destroy, id: @lead.id
          expect(flash[:warning]).not_to eq(nil)
          expect(response.body).to eq("window.location.reload();")
        end

        it "should reload current page with the flash message if the lead is protected" do
          @private = FactoryGirl.create(:lead, user: FactoryGirl.create(:user), access: "Private")

          xhr :delete, :destroy, id: @private.id
          expect(flash[:warning]).not_to eq(nil)
          expect(response.body).to eq("window.location.reload();")
        end
      end
    end

    describe "HTML request" do
      it "should redirect to Leads index when a lead gets deleted from its landing page" do
        delete :destroy, id: @lead.id
        expect(flash[:notice]).not_to eq(nil)
        expect(session[:leads_current_page]).to eq(1)
        expect(response).to redirect_to(leads_path)
      end

      it "should redirect to lead index with the flash message is the lead got deleted" do
        @lead = FactoryGirl.create(:lead, user: current_user)
        @lead.destroy

        delete :destroy, id: @lead.id
        expect(flash[:warning]).not_to eq(nil)
        expect(response).to redirect_to(leads_path)
      end

      it "should redirect to lead index with the flash message if the lead is protected" do
        @private = FactoryGirl.create(:lead, user: FactoryGirl.create(:user), access: "Private")

        delete :destroy, id: @private.id
        expect(flash[:warning]).not_to eq(nil)
        expect(response).to redirect_to(leads_path)
      end
    end
  end

  # GET /leads/1/convert
  # GET /leads/1/convert.xml                                               AJAX
  #----------------------------------------------------------------------------
  describe "responding to GET convert" do
    it "should should collect necessary data and render [convert] template" do
      @campaign = FactoryGirl.create(:campaign, user: current_user)
      @lead = FactoryGirl.create(:lead, user: current_user, campaign: @campaign, source: "cold_call")
      @accounts = [FactoryGirl.create(:account, user: current_user)]
      @account = Account.new(user: current_user, name: @lead.company, access: "Lead")
      @opportunity = Opportunity.new(user: current_user, access: "Lead", stage: "prospecting", campaign: @lead.campaign, source: @lead.source)

      xhr :get, :convert, id: @lead.id
      expect(assigns[:lead]).to eq(@lead)
      expect(assigns[:accounts]).to eq(@accounts)
      expect(assigns[:account].attributes).to eq(@account.attributes)
      expect(assigns[:opportunity].attributes).to eq(@opportunity.attributes)
      expect(assigns[:opportunity].campaign).to eq(@opportunity.campaign)
      expect(response).to render_template("leads/convert")
    end

    describe "(lead got deleted or is otherwise unavailable)" do
      it "should reload current page with the flash message if the lead got deleted" do
        @lead = FactoryGirl.create(:lead, user: current_user)
        @lead.destroy

        xhr :get, :convert, id: @lead.id
        expect(flash[:warning]).not_to eq(nil)
        expect(response.body).to eq("window.location.reload();")
      end

      it "should reload current page with the flash message if the lead is protected" do
        @private = FactoryGirl.create(:lead, user: FactoryGirl.create(:user), access: "Private")

        xhr :get, :convert, id: @private.id
        expect(flash[:warning]).not_to eq(nil)
        expect(response.body).to eq("window.location.reload();")
      end
    end

    describe "(previous lead got deleted or is otherwise unavailable)" do
      before(:each) do
        @lead = FactoryGirl.create(:lead, user: current_user)
        @previous = FactoryGirl.create(:lead, user: FactoryGirl.create(:user))
      end

      it "should notify the view if previous lead got deleted" do
        @previous.destroy

        xhr :get, :convert, id: @lead.id, previous: @previous.id
        expect(flash[:warning]).to eq(nil) # no warning, just silently remove the div
        expect(assigns[:previous]).to eq(@previous.id)
        expect(response).to render_template("leads/convert")
      end

      it "should notify the view if previous lead got protected" do
        @previous.update_attribute(:access, "Private")

        xhr :get, :convert, id: @lead.id, previous: @previous.id
        expect(flash[:warning]).to eq(nil)
        expect(assigns[:previous]).to eq(@previous.id)
        expect(response).to render_template("leads/convert")
      end
    end
  end

  # PUT /leads/1/promote
  # PUT /leads/1/promote.xml                                               AJAX
  #----------------------------------------------------------------------------
  describe "responding to PUT promote" do
    it "on success: should change lead's status to [converted] and render [promote] template" do
      @lead = FactoryGirl.create(:lead, id: 42, user: current_user, campaign: nil)
      @account = FactoryGirl.create(:account, id: 123, user: current_user)
      @opportunity = FactoryGirl.build(:opportunity, user: current_user, campaign: @lead.campaign,
                                                     account: @account)
      allow(Opportunity).to receive(:new).and_return(@opportunity)
      @contact = FactoryGirl.build(:contact, user: current_user, lead: @lead)
      allow(Contact).to receive(:new).and_return(@contact)

      xhr :put, :promote, id: 42, account: { id: 123 }, opportunity: { name: "Hello" }
      expect(@lead.reload.status).to eq("converted")
      expect(assigns[:lead]).to eq(@lead)
      expect(assigns[:account]).to eq(@account)
      expect(assigns[:accounts]).to eq([@account])
      expect(assigns[:opportunity]).to eq(@opportunity)
      expect(assigns[:contact]).to eq(@contact)
      expect(assigns[:stage]).to be_instance_of(Array)
      expect(response).to render_template("leads/promote")
    end

    it "should copy lead permissions to newly created account and opportunity when asked so" do
      he  = FactoryGirl.create(:user, id: 7)
      she = FactoryGirl.create(:user, id: 8)
      @lead = FactoryGirl.build(:lead, access: "Shared")
      @lead.permissions << FactoryGirl.build(:permission, user: he,  asset: @lead)
      @lead.permissions << FactoryGirl.build(:permission, user: she, asset: @lead)
      @lead.save
      @account = FactoryGirl.build(:account, user: current_user, access: "Shared")
      @account.permissions << FactoryGirl.create(:permission, user: he,  asset: @account)
      @account.permissions << FactoryGirl.create(:permission, user: she, asset: @account)
      allow(@account).to receive(:new).and_return(@account)
      @opportunity = FactoryGirl.build(:opportunity, user: current_user, access: "Shared")
      @opportunity.permissions << FactoryGirl.create(:permission, user: he,  asset: @opportunity)
      @opportunity.permissions << FactoryGirl.create(:permission, user: she, asset: @opportunity)
      allow(@opportunity).to receive(:new).and_return(@opportunity)

      xhr :put, :promote, id: @lead.id, access: "Lead", account: { name: "Hello", access: "Lead", user_id: current_user.id }, opportunity: { name: "World", access: "Lead", user_id: current_user.id }
      expect(@account.access).to eq("Shared")
      expect(@account.permissions.map(&:user_id).sort).to eq([7, 8])
      expect(@account.permissions.map(&:asset_id)).to eq([@account.id, @account.id])
      expect(@account.permissions.map(&:asset_type)).to eq(%w(Account Account))
      expect(@opportunity.access).to eq("Shared")
      expect(@opportunity.permissions.map(&:user_id).sort).to eq([7, 8])
      expect(@opportunity.permissions.map(&:asset_id)).to eq([@opportunity.id, @opportunity.id])
      expect(@opportunity.permissions.map(&:asset_type)).to eq(%w(Opportunity Opportunity))
    end

    it "should assign lead's campaign to the newly created opportunity" do
      @campaign = FactoryGirl.create(:campaign)
      @lead = FactoryGirl.create(:lead, user: current_user, campaign: @campaign)

      xhr :put, :promote, id: @lead.id, account: { name: "Hello" }, opportunity: { name: "Hello", campaign_id: @campaign.id }
      expect(assigns[:opportunity].campaign).to eq(@campaign)
    end

    it "should assign lead's source to the newly created opportunity" do
      @lead = FactoryGirl.create(:lead, user: current_user, source: "cold_call")

      xhr :put, :promote, id: @lead.id, account: { name: "Hello" }, opportunity: { name: "Hello", source: @lead.source }
      expect(assigns[:opportunity].source).to eq(@lead.source)
    end

    it "should get the data for leads sidebar when called from leads index" do
      @lead = FactoryGirl.create(:lead)
      request.env["HTTP_REFERER"] = "http://localhost/leads"

      xhr :put, :promote, id: @lead.id, account: { name: "Hello" }, opportunity: {}
      expect(assigns[:lead_status_total]).not_to be_nil
      expect(assigns[:lead_status_total]).to be_an_instance_of(HashWithIndifferentAccess)
    end

    it "should reload lead campaign if called from campaign landing page" do
      @campaign = FactoryGirl.create(:campaign)
      @lead = FactoryGirl.create(:lead, campaign: @campaign)
      request.env["HTTP_REFERER"] = "http://localhost/campaigns/#{@campaign.id}"

      xhr :put, :promote, id: @lead.id, account: { name: "Hello" }, opportunity: {}
      expect(assigns[:campaign]).to eq(@campaign)
    end

    it "on failure: should not change lead's status and still render [promote] template" do
      @lead = FactoryGirl.create(:lead, id: 42, user: current_user, status: "new")
      @account = FactoryGirl.create(:account, id: 123, user: current_user)
      @contact = FactoryGirl.build(:contact, first_name: nil) # make it fail
      allow(Contact).to receive(:new).and_return(@contact)

      xhr :put, :promote, id: 42, account: { id: 123 }
      expect(@lead.reload.status).to eq("new")
      expect(response).to render_template("leads/promote")
    end

    describe "lead got deleted or otherwise unavailable" do
      it "should reload current page with the flash message if the lead got deleted" do
        @lead = FactoryGirl.create(:lead, user: current_user)
        @lead.destroy

        xhr :put, :promote, id: @lead.id
        expect(flash[:warning]).not_to eq(nil)
        expect(response.body).to eq("window.location.reload();")
      end

      it "should reload current page with the flash message if the lead is protected" do
        @private = FactoryGirl.create(:lead, user: FactoryGirl.create(:user), access: "Private")

        xhr :put, :promote, id: @private.id
        expect(flash[:warning]).not_to eq(nil)
        expect(response.body).to eq("window.location.reload();")
      end
    end
  end

  # PUT /leads/1/reject
  # PUT /leads/1/reject.xml                                       AJAX and HTML
  #----------------------------------------------------------------------------
  describe "responding to PUT reject" do
    before(:each) do
      @lead = FactoryGirl.create(:lead, user: current_user, status: "new")
    end

    describe "AJAX request" do
      it "should reject the requested lead and render [reject] template" do
        xhr :put, :reject, id: @lead.id

        expect(assigns[:lead]).to eq(@lead.reload)
        expect(@lead.status).to eq("rejected")
        expect(response).to render_template("leads/reject")
      end

      it "should get the data for leads sidebar when called from leads index" do
        request.env["HTTP_REFERER"] = "http://localhost/leads"
        xhr :put, :reject, id: @lead.id
        expect(assigns[:lead_status_total]).not_to be_nil
        expect(assigns[:lead_status_total]).to be_an_instance_of(HashWithIndifferentAccess)
      end

      it "should reload lead campaign if called from campaign landing page" do
        @campaign = FactoryGirl.create(:campaign)
        @lead = FactoryGirl.create(:lead, campaign: @campaign)

        request.env["HTTP_REFERER"] = "http://localhost/campaigns/#{@campaign.id}"
        xhr :put, :reject, id: @lead.id
        expect(assigns[:campaign]).to eq(@campaign)
      end

      describe "lead got deleted or otherwise unavailable" do
        it "should reload current page with the flash message if the lead got deleted" do
          @lead = FactoryGirl.create(:lead, user: current_user)
          @lead.destroy

          xhr :put, :reject, id: @lead.id
          expect(flash[:warning]).not_to eq(nil)
          expect(response.body).to eq("window.location.reload();")
        end

        it "should reload current page with the flash message if the lead is protected" do
          @private = FactoryGirl.create(:lead, user: FactoryGirl.create(:user), access: "Private")

          xhr :put, :reject, id: @private.id
          expect(flash[:warning]).not_to eq(nil)
          expect(response.body).to eq("window.location.reload();")
        end
      end
    end

    describe "HTML request" do
      it "should redirect to Leads index when a lead gets rejected from its landing page" do
        put :reject, id: @lead.id

        expect(assigns[:lead]).to eq(@lead.reload)
        expect(@lead.status).to eq("rejected")
        expect(flash[:notice]).not_to eq(nil)
        expect(response).to redirect_to(leads_path)
      end

      describe "lead got deleted or otherwise unavailable" do
        it "should redirect to lead index if the lead got deleted" do
          @lead = FactoryGirl.create(:lead, user: current_user)
          @lead.destroy

          put :reject, id: @lead.id
          expect(flash[:warning]).not_to eq(nil)
          expect(response).to redirect_to(leads_path)
        end

        it "should redirect to lead index if the lead is protected" do
          @private = FactoryGirl.create(:lead, user: FactoryGirl.create(:user), access: "Private")

          put :reject, id: @private.id
          expect(flash[:warning]).not_to eq(nil)
          expect(response).to redirect_to(leads_path)
        end
      end
    end
  end

  # PUT /leads/1/attach
  # PUT /leads/1/attach.xml                                                AJAX
  #----------------------------------------------------------------------------
  describe "responding to PUT attach" do
    describe "tasks" do
      before do
        @model = FactoryGirl.create(:lead)
        @attachment = FactoryGirl.create(:task, asset: nil)
      end
      it_should_behave_like("attach")
    end
  end

  # PUT /leads/1/attach
  # PUT /leads/1/attach.xml                                                AJAX
  #----------------------------------------------------------------------------
  describe "responding to PUT attach" do
    describe "tasks" do
      before do
        @model = FactoryGirl.create(:lead)
        @attachment = FactoryGirl.create(:task, asset: nil)
      end
      it_should_behave_like("attach")
    end
  end

  # POST /leads/1/discard
  # POST /leads/1/discard.xml                                              AJAX
  #----------------------------------------------------------------------------
  describe "responding to POST discard" do
    before(:each) do
      @attachment = FactoryGirl.create(:task, assigned_to: current_user)
      @model = FactoryGirl.create(:lead)
      @model.tasks << @attachment
    end

    it_should_behave_like("discard")
  end

  # POST /leads/auto_complete/query                                        AJAX
  #----------------------------------------------------------------------------
  describe "responding to POST auto_complete" do
    before(:each) do
      @auto_complete_matches = [FactoryGirl.create(:lead, first_name: "Hello", last_name: "World", user: current_user)]
    end

    it_should_behave_like("auto complete")
  end

  # GET /leads/redraw                                                      AJAX
  #----------------------------------------------------------------------------
  describe "responding to GET redraw" do
    it "should save user selected lead preference" do
      xhr :get, :redraw, per_page: 42, view: "long", sort_by: "first_name", naming: "after"
      expect(current_user.preference[:leads_per_page]).to eq("42")
      expect(current_user.preference[:leads_index_view]).to eq("long")
      expect(current_user.preference[:leads_sort_by]).to eq("leads.first_name ASC")
      expect(current_user.preference[:leads_naming]).to eq("after")
    end

    it "should set similar options for Contacts" do
      xhr :get, :redraw, sort_by: "first_name", naming: "after"
      expect(current_user.pref[:contacts_sort_by]).to eq("contacts.first_name ASC")
      expect(current_user.pref[:contacts_naming]).to eq("after")
    end

    it "should reset current page to 1" do
      xhr :get, :redraw, per_page: 42, view: "long", sort_by: "first_name", naming: "after"
      expect(session[:leads_current_page]).to eq(1)
    end

    it "should select @leads and render [index] template" do
      @leads = [
        FactoryGirl.create(:lead, first_name: "Alice", user: current_user),
        FactoryGirl.create(:lead, first_name: "Bobby", user: current_user)
      ]

      xhr :get, :redraw, per_page: 1, sort_by: "first_name"
      expect(assigns(:leads)).to eq([@leads.first])
      expect(response).to render_template("leads/index")
    end
  end

  # POST /leads/filter                                                     AJAX
  #----------------------------------------------------------------------------
  describe "responding to POST filter" do
    it "should filter out leads as @leads and render :index action" do
      session[:leads_filter] = "contacted,rejected"

      @leads = [FactoryGirl.create(:lead, user: current_user, status: "new")]
      xhr :post, :filter, status: "new"
      expect(assigns[:leads]).to eq(@leads)
      expect(response).to be_a_success
      expect(response).to render_template("leads/index")
    end

    it "should reset current page to 1" do
      @leads = []
      xhr :post, :filter, status: "new"

      expect(session[:leads_current_page]).to eq(1)
    end
  end
end
