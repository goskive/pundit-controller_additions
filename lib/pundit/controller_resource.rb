module Pundit
  # Handle the load and authorization controller logic so we don't clutter up all controllers with non-interface methods.
  # This class is used internally, so you do not need to call methods directly on it.
  class ControllerResource # :nodoc:
    def self.add_before_filter(controller_class, method, *args)
      options = args.extract_options!
      resource_name = args.first
      before_filter_method = options.delete(:prepend) ? :prepend_before_filter : :before_filter
      controller_class.send(before_filter_method, options.slice(:only, :except, :if, :unless)) do |controller|
        controller.class.cancan_resource_class.new(controller, resource_name, options.except(:only, :except, :if, :unless)).send(method)
      end
    end

    def initialize(controller, *args)
      @controller = controller
      @params = controller.params
      @options = args.extract_options!
      @name = args.first
    end

    def load_and_authorize_resource
      load_resource
      authorize_resource
    end

    def load_resource
      unless skip?(:load)
        if load_instance?
          self.resource_instance ||= load_resource_instance
        elsif load_collection?
          self.collection_instance ||= load_collection
        end
      end
    end

    def authorize_resource
      unless skip?(:authorize)
        if resource_instance
          @controller.authorize(resource_instance, :"#{authorization_action}?")
        else
          # TODO: fix authorization when parent resource present
          Rails.logger.warn "Skipping authorization for #{resource_class_with_parent}"
        end
      end
    end

    def parent?
      @options.key?(:parent) ? @options[:parent] : @name && @name != name_from_controller.to_sym
    end

    def skip?(behavior)
      return false unless options = @controller.class.cancan_skipper[behavior][@name]

      options == {} ||
        options[:except] && !action_exists_in?(options[:except]) ||
        action_exists_in?(options[:only])
    end

    protected

    def load_resource_instance
      if !parent? && new_actions.include?(@params[:action].to_sym)
        build_resource
      elsif id_param || @options[:singleton]
        find_resource
      end
    end

    def load_instance?
      parent? || member_action?
    end

    def load_collection?
      resource_base.is_a?(ActiveRecord::Relation)
    end

    def load_collection
      @controller.policy_scope(resource_base)
    end

    def build_resource
      resource = resource_base.new(resource_params || {})
      assign_attributes(resource)
    end

    def assign_attributes(resource)
      resource.send("#{parent_name}=", parent_resource) if @options[:singleton] && parent_resource
      resource
    end

    def find_resource
      if @options[:singleton] && parent_resource.respond_to?(name)
        parent_resource.send(name)
      else
        if @options[:find_by]
          if resource_base.respond_to? "find_by_#{@options[:find_by]}!"
            resource_base.send("find_by_#{@options[:find_by]}!", id_param)
          elsif resource_base.respond_to? 'find_by'
            resource_base.send('find_by', @options[:find_by].to_sym => id_param)
          else
            resource_base.send(@options[:find_by], id_param)
          end
        else
          resource_base.find(id_param)
        end
      end
    end

    def authorization_action
      parent? ? parent_authorization_action : @params[:action].to_sym
    end

    def parent_authorization_action
      @options[:parent_action] || :show
    end

    def id_param
      @params[id_param_key].to_s if @params[id_param_key]
    end

    def id_param_key
      if @options[:id_param]
        @options[:id_param]
      else
        parent? ? :"#{name}_id" : :id
      end
    end

    def member_action?
      new_actions.include?(@params[:action].to_sym) || @options[:singleton] || ((@params[:id] || @params[@options[:id_param]]) && !collection_actions.include?(@params[:action].to_sym))
    end

    # Returns the class used for this resource. This can be overriden by the :class option.
    # If +false+ is passed in it will use the resource name as a symbol in which case it should
    # only be used for authorization, not loading since there's no class to load through.
    def resource_class
      case @options[:class]
      when false  then name.to_sym
      when nil    then namespaced_name.to_s.camelize.constantize
      when String then @options[:class].constantize
      else @options[:class]
      end
    end

    def resource_class_with_parent
      parent_resource ? { parent_resource => resource_class } : resource_class
    end

    def resource_instance=(instance)
      @controller.instance_variable_set("@#{instance_name}", instance)
    end

    def resource_instance
      @controller.instance_variable_get("@#{instance_name}") if load_instance?
    end

    def collection_instance=(instance)
      @controller.instance_variable_set("@#{instance_name.to_s.pluralize}", instance)
    end

    def collection_instance
      @controller.instance_variable_get("@#{instance_name.to_s.pluralize}")
    end

    # The object that methods (such as "find", "new" or "build") are called on.
    # If the :through option is passed it will go through an association on that instance.
    # If the :shallow option is passed it will use the resource_class if there's no parent
    # If the :singleton option is passed it won't use the association because it needs to be handled later.
    def resource_base
      if @options[:through]
        if parent_resource
          base = @options[:singleton] ? resource_class : parent_resource.send(@options[:through_association] || name.to_s.pluralize)
          base = base.scoped if base.respond_to?(:scoped) && defined?(ActiveRecord) && ActiveRecord::VERSION::MAJOR == 3
          base
        elsif @options[:shallow]
          resource_class
        else
          fail NotAuthorizedError.new(query: authorization_action, record: resource_class)
        end
      else
        resource_class
      end
    end

    def parent_name
      @options[:through] && [@options[:through]].flatten.detect { |i| fetch_parent(i) }
    end

    # The object to load this resource through.
    def parent_resource
      parent_name && fetch_parent(parent_name)
    end

    def fetch_parent(name)
      if @controller.instance_variable_defined? "@#{name}"
        @controller.instance_variable_get("@#{name}")
      elsif @controller.respond_to?(name, true)
        @controller.send(name)
      end
    end

    def name
      @name || name_from_controller
    end

    def resource_params
      if parameters_require_sanitizing? && params_method.present?
        return case params_method
               when Symbol then @controller.send(params_method)
               when String then @controller.instance_eval(params_method)
               when Proc then params_method.call(@controller)
        end
      else
        resource_params_by_namespaced_name
      end
    end

    def parameters_require_sanitizing?
      save_actions.include?(@params[:action].to_sym) || resource_params_by_namespaced_name.present?
    end

    def resource_params_by_namespaced_name
      if @options[:instance_name] && @params.key?(extract_key(@options[:instance_name]))
        @params[extract_key(@options[:instance_name])]
      elsif @options[:class] && @params.key?(extract_key(@options[:class]))
        @params[extract_key(@options[:class])]
      else
        @params[extract_key(namespaced_name)]
      end
    end

    def params_method
      params_methods.each do |method|
        return method if (method.is_a?(Symbol) && @controller.respond_to?(method, true)) || method.is_a?(String) || method.is_a?(Proc)
      end
      nil
    end

    def params_methods
      methods = ["#{@params[:action]}_params".to_sym, "#{name}_params".to_sym, :resource_params]
      methods.unshift(@options[:param_method]) if @options[:param_method].present?
      methods
    end

    def namespace
      @params[:controller].split('/')[0..-2]
    end

    def namespaced_name
      [namespace, name.camelize].flatten.map(&:camelize).join('::').singularize.constantize
    rescue NameError
      name
    end

    def name_from_controller
      @params[:controller].split('/').last.singularize
    end

    def instance_name
      @options[:instance_name] || name
    end

    def collection_actions
      [:index] + Array(@options[:collection])
    end

    def new_actions
      [:new, :create] + Array(@options[:new])
    end

    def save_actions
      [:create, :update]
    end

    private

    def action_exists_in?(options)
      Array(options).include?(@params[:action].to_sym)
    end

    def extract_key(value)
      value.to_s.underscore.gsub('/', '_')
    end
  end
end