require 'redmine'
require 'dispatcher'
require 'time_entries_query_patch'

unless Redmine::Plugin.registered_plugins.keys.include?(:time_entries_query_operators)
	Redmine::Plugin.register :time_entries_query_operators do
		name 'Time entries query operators plugin'
		author 'Nikita Vasiliev'
		author_url 'mailto:sharpyfox@gmail.com'
		description 'Redmine plugin which add filters by time_entries'
		version '0.0.1'
		requires_redmine :version_or_higher => '1.3.0'
	end
end

Dispatcher.to_prepare :time_entries_query_operators do
  require_dependency 'issue'
  require_dependency 'time_entry'    
  require_dependency 'query'    

  unless Issue.included_modules.include? TimeEntryQuery::Patches::IssueModelPatch
    Issue.send(:include, TimeEntryQuery::Patches::IssueModelPatch)
  end
  
  unless TimeEntry.included_modules.include? TimeEntryQuery::Patches::TimeEntryModelPatch
    TimeEntry.send(:include, TimeEntryQuery::Patches::TimeEntryModelPatch)
  end
  
  unless Query.included_modules.include? TimeEntryQuery::Patches::QueryModelPatch
    Query.send(:include, TimeEntryQuery::Patches::QueryModelPatch)
  end
end
