# This file is a part of Redmine Tags (redmine_tags) plugin,
# customer relationship management plugin for Redmine
#
# Copyright (C) 2011-2025 RedmineUP
# http://www.redmineup.com/
#
# redmine_tags is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# redmine_tags is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with redmine_tags.  If not, see <http://www.gnu.org/licenses/>.

module RedmineupTags
  module Patches
    module TimeEntryQueryPatch
      def self.included(base)
        base.send(:include, InstanceMethods)

        base.class_eval do
          alias_method :statement_without_redmine_tags, :statement
          alias_method :statement, :statement_with_redmine_tags

          alias_method :available_filters_without_redmine_tags, :available_filters
          alias_method :available_filters, :available_filters_with_redmine_tags

          add_available_column QueryTagsColumn.new(:tags_relations, caption: :tags)
        end
      end

      module InstanceMethods
        def statement_with_redmine_tags
          filter  = filters.delete 'issue_tags'
          clauses = statement_without_redmine_tags || ''

          if filter
            filters['issue_tags'] = filter

            issues = Issue.where({})

            op = operator_for('issue_tags')
            case op
            when '=', '!'
              issues = issues.tagged_with(values_for('issue_tags').clone, match_all: true)
            when '!*'
              issues = issues.joins(:tags).uniq
            else
              issues = issues.tagged_with(Redmineup::Tag.all.map(&:to_s), any: true)
            end

            compare   = op.include?('!') ? 'NOT IN' : 'IN'
            ids_list  = issues.collect(&:id).push(0).join(',')

            clauses << ' AND ' unless clauses.empty?
            clauses << "( #{Issue.table_name}.id #{compare} (#{ids_list}) ) "
          end

          clauses
        end

        def available_filters_with_redmine_tags
          available_filters_without_redmine_tags
          selected_tags = []
          if filters['issue_tags'].present?
            selected_tags = Issue.all_tags(project: project, open_only: RedmineupTags.settings['issues_open_only'].to_i == 1).
                            where(name: filters['issue_tags'][:values]).map { |c| [c.name, c.name] }
          end
          add_available_filter('issue_tags', type: :issue_tags, name: l(:tags), values: selected_tags)
        end
      end
    end
  end
end

if (ActiveRecord::Base.connection.tables.include?('queries') rescue false) &&
   TimeEntryQuery.included_modules.exclude?(RedmineupTags::Patches::TimeEntryQueryPatch)
  TimeEntryQuery.send(:include, RedmineupTags::Patches::TimeEntryQueryPatch)
end
