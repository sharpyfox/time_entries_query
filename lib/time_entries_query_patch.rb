module TimeEntryQuery  
	module Patches		
		module QueryModelPatch
			def self.included(base) # :nodoc:
				base.extend(ClassMethods)
				base.send(:include, InstanceMethods)

				base.class_eval do					
					alias_method_chain :available_filters, :time_entry_patch
					alias_method_chain :available_columns, :time_entry_patch
					alias_method_chain :issues, :time_entry_patch
				end
			end
      
			module ClassMethods
				#dummy
			end
      
			module InstanceMethods
				def available_columns_with_time_entry_patch
					columns = available_columns_without_time_entry_patch
					columns.each_with_index {|column, i| return columns if column.name == :time_by_users}			
					columns.push(QueryColumn.new(:time_by_users, :sortable => "#{Issue.table_name}.created_on", :default_order => 'desc', :caption => :label_time_corrected))
					return columns
				end
				
				def available_filters_with_time_entry_patch
					f = available_filters_without_time_entry_patch
					
					principals = []
					if project
						principals += project.principals.sort
						unless project.leaf?
							subprojects = project.descendants.visible.all
							if subprojects.any?
								@available_filters["subproject_id"] = { :type => :list_subprojects, :order => 13, :values => subprojects.collect{|s| [s.name, s.id.to_s] } }
								principals += Principal.member_of(subprojects)
							end
						end
					else
						all_projects = Project.visible.all
						if all_projects.any?
							# members of visible projects
							principals += Principal.member_of(all_projects)

							# project filter
							project_values = []
							if User.current.logged? && User.current.memberships.any?
								project_values << ["<< #{l(:label_my_projects).downcase} >>", "mine"]
							end
							Project.project_tree(all_projects) do |p, level|
								prefix = (level > 0 ? ('--' * level + ' ') : '')
								project_values << ["#{prefix}#{p.name}", p.id.to_s]
							end
							@available_filters["project_id"] = { :type => :list, :order => 1, :values => project_values} unless project_values.empty?
						end
					end
					principals.uniq!
					principals.sort!
					users = principals.select {|p| p.is_a?(User)}
					
					users_values = []
					users_values << ["<< #{l(:label_i_am)} >>", "me"] if User.current.logged?
					users_values += (Setting.issue_group_assignment? ? principals : users).collect{|s| [s.name, s.id.to_s] }
					f["time_entries_users"] = { :type => :list, :order => 25, :values => users_values}          
					f["time_entries_dates"] = { :type => :date, :order => 26}          
					f # return
				end
				
				def condition_for_time_entries_dates_field(operator, value)
					field = 'time_entries_dates' 
					db_table = TimeEntry.table_name
					sql_for_field(field, operator, value, db_table, 'spent_on')
				end

				def sql_for_time_entries_users_field(field, operator, value)
					sql = case operator
						when "="						
							sql = "#{Issue.table_name}.id IN (SELECT DISTINCT #{TimeEntry.table_name}.issue_id FROM #{TimeEntry.table_name} WHERE #{TimeEntry.table_name}.user_id IN (" + value.collect{|val| "'#{connection.quote_string(val)}'"}.join(",") + "))"
						when "!="						
							sql = "#{Issue.table_name}.id NOT IN (SELECT DISTINCT #{TimeEntry.table_name}.issue_id FROM #{TimeEntry.table_name} WHERE #{TimeEntry.table_name}.user_id IN (" + value.collect{|val| "'#{connection.quote_string(val)}'"}.join(",") + "))"
						else					
							# IN an empty set
							sql = "1=0"
					end			
					sql
				end
		
				def sql_for_time_entries_dates_field(field, operator, value)
					db_table = TimeEntry.table_name
					"#{Issue.table_name}.id IN (SELECT DISTINCT #{TimeEntry.table_name}.issue_id FROM #{TimeEntry.table_name} WHERE (" + sql_for_field(field, operator, value, db_table, 'spent_on') + '))'
				end
		
				def issues_with_time_entry_patch(options={})
					issues = issues_without_time_entry_patch(options)
			
					if has_column?(:time_by_users)
						users = values_for('time_entries_users') || []
						zCondition = condition_for_time_entries_dates_field(operator_for('time_entries_dates'), value_for('time_entries_dates')) || ''
						Issue.load_visible_spent_hours_by_users(issues, users, zCondition)
					end
		
					issues
				end
			end        
		end
	module TimeEntryModelPatch				
		def self.included(base) # :nodoc:
			base.extend(ClassMethods)
			base.send(:include, InstanceMethods) #dummy			
		end
		
		module ClassMethods			
			ActiveRecord::Base.named_scope :spent_by_users, lambda {|by_users| {	 
				:conditions => [" #{TimeEntry.table_name}.user_id IN (" + by_users.collect{|u| "'#{u}'"}.join(",") + ") "]	 
			}}
  
			ActiveRecord::Base.named_scope :free_condition, lambda {|aCondition| {	 
				:conditions => [aCondition]	 
			}}						
		end
		
		module InstanceMethods
			#
		end
	end
	module IssueModelPatch
		def self.included(base) # :nodoc:
			base.extend(ClassMethods)
			base.send(:include, InstanceMethods)
		end
		
		module ClassMethods			
	
			def load_visible_spent_hours_by_users(issues, users, aCondition, user=User.current)	
				if issues.any?    	
					hours_by_issue_id = TimeEntry.visible(user).spent_by_users(users).free_condition(aCondition).sum(:hours, :group => :issue_id)
					issues.each do |issue|
						issue.instance_variable_set "@time_by_users", (hours_by_issue_id[issue.id] || 0)		
					end
				end
			end
		end
		
		module InstanceMethods
			def time_by_users
				if @time_by_users.is_a?(Float)
					@time_by_users.round(2)
				else
					@time_by_users
				end	
			end
		end
	end
  end
end