# This file is a part of Redmin Agile (redmine_agile) plugin,
# Agile board plugin for redmine
#
# Copyright (C) 2011-2025 RedmineUP
# http://www.redmineup.com/
#
# redmine_agile is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# redmine_agile is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with redmine_agile.  If not, see <http://www.gnu.org/licenses/>.

class AgileBoardsController < ApplicationController
  menu_item :agile

  before_action :find_issue, only: [:update, :issue_tooltip, :inline_comment, :edit_issue, :update_issue, :agile_data]
  before_action :find_optional_project, only: [
                                               :index,
                                               :create_issue,
                                              ]
  before_action :authorize, except: [:index, :edit_issue, :update_issue]

  accept_api_auth :agile_data

  helper :issues
  helper :journals
  helper :projects
  include ProjectsHelper
  helper :custom_fields
  include CustomFieldsHelper
  helper :issue_relations
  include IssueRelationsHelper
  helper :watchers
  include WatchersHelper
  helper :attachments
  include AttachmentsHelper
  helper :queries
  include QueriesHelper
  helper :repositories
  include RepositoriesHelper
  helper :sort
  include SortHelper
  include IssuesHelper
  helper :timelog
  include RedmineAgile::Helpers::AgileHelper
  helper :checklists if RedmineAgile.use_checklist?

  def index
    retrieve_agile_query
    if @query.valid?
      @issues = @query.issues
      @agile_projects = @query.agile_projects
      @issue_board = @query.issue_board
      @board_columns = @query.board_statuses
      @allowed_statuses = statuses_allowed_for_create

      respond_to do |format|
        format.html { render :template => 'agile_boards/index', :layout => !request.xhr? }
        format.js
      end
    else
      respond_to do |format|
        format.html { render(:template => 'agile_boards/index', :layout => !request.xhr?) }
        format.js
      end
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def update
    (render_error_message(l(:label_agile_action_not_available)); return false) unless @issue.editable?
    retrieve_agile_query_from_session
    old_status = @issue.status
    @issue.init_journal(User.current)

    @issue.safe_attributes = configured_params['issue']

    saved = configured_params['issue'] && configured_params['issue'].inject(true) do |total, attribute|
      if @issue.attributes.include?(attribute.first)
        total &&= @issue.attributes[attribute.first].to_i == attribute.last.to_i
      else
        total &&= true
      end
    end
    call_hook(:controller_agile_boards_update_before_save, { params: params, issue: @issue})
    @update = true
    if saved && @issue.save
      call_hook(:controller_agile_boards_update_after_save, { :params => params, :issue => @issue})
      AgileData.transaction do
        Issue.eager_load(:agile_data).find(params[:positions].keys).each do |issue|
          issue.agile_data.position = params[:positions][issue.id.to_s]['position']
          issue.agile_data.save
        end
      end if params[:positions]

      @inline_adding = params[:issue][:notes] || nil

      web_socket_service_update(params, @issue, { query: @query, project: @project })
      respond_to do |format|
        format.html { render(:partial => 'issue_card', :locals => {:issue => @issue}, :status => :ok, :layout => nil) }
      end
    else
      respond_to do |format|
        messages = @issue.errors.full_messages
        messages = [l(:text_agile_move_not_possible)] if messages.empty?
        format.html {
          render json: messages, status: :unprocessable_entity, layout: nil
        }
      end
    end
  end

  def issue_tooltip
    render :partial => 'issue_tooltip'
  end

  def inline_comment
    render 'inline_comment', :layout => nil
  end

  def agile_data
    @agile_data = @issue.agile_data
    return render_404 unless @agile_data

    respond_to do |format|
      format.any { head :ok }
      format.api { }
    end
  end

  private

  def configured_params
    return @configured_params if @configured_params

    issue_params = params[:issue]
    issue_params[:parent_issue_id] = issue_params[:parent_id] && issue_params.delete(:parent_id) if issue_params[:parent_id]
    issue_params[:assigned_to_id] = User.current.id if auto_assign_on_move?

    @configured_params = params.respond_to?(:to_unsafe_hash) ? params.to_unsafe_hash : params
  end

  def auto_assign_on_move?
    RedmineAgile.auto_assign_on_move? && @issue.assigned_to.nil? &&
      !params[:issue].keys.include?('assigned_to_id') &&
      @issue.status_id != params[:issue]['status_id'].to_i
  end

  def statuses_allowed_for_create
    issue = Issue.new(project: @project)
    issue.tracker = issue_tracker(issue)
    issue.new_statuses_allowed_to
  end

  def issue_tracker(issue)
    return issue.allowed_target_trackers.first if issue.respond_to?(:allowed_target_trackers)
    return @project.trackers.first if @project
    nil
  end

  def render_error_message(message)
    render json: [message], status: :unprocessable_entity
  end
end
