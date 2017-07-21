# This simple Rack middleware subscribes to all AS::Notifications
# and adds the appropriate `Server-Timing` header as described in
# the spec [1] with the notifications grouped by name and with the
# elapsed time added up.
#
# [1] Server Timing spec: https://w3c.github.io/server-timing/

module Rack
  class ServerTimingMiddleware
    def initialize(app)
      @app = app
    end
    def call(env)

      events = []

      subs = ActiveSupport::Notifications.subscribe(/(process_action.action_controller|sql.active_record)/) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      status, headers, body = @app.call(env)

      # As the doc states, this harms the internal AS:Notifications
      # caches, but I'd say it's necessary so we don't leak memory
      ActiveSupport::Notifications.unsubscribe(subs)
      sql_events = events.select{|event| event.name == 'sql.active_record' && event.payload[:name] != 'SCHEMA'}
      controller_events = events.select{|event| event.name == 'process_action.action_controller'}
      
      #ignore assets
      if controller_events[0]
        view_runtime_payload = controller_events[0].payload[:view_runtime] 
        db_runtime_payload = controller_events[0].payload[:db_runtime] 

        if view_runtime_payload
          view_runtime = '%.0f' % view_runtime_payload
          headers['X-View-Runtime'] =  view_runtime
        end

        if db_runtime_payload
          db_runtime = '%.0f' % db_runtime_payload
          headers['X-Db-Runtime'] =  db_runtime
        end
      end

      sql_queries = sql_events.size
      headers['X-Sql-Queries'] = sql_queries

      [status, headers, body]
    end
  end
end
