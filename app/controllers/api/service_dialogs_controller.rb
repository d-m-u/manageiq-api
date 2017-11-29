module Api
  class ServiceDialogsController < BaseController
    before_action :set_additional_attributes, :only => [:index, :show]

    CONTENT_PARAMS = %w[target_type target_id resource_action_id].freeze

    def refresh_dialog_fields_resource(type, id = nil, data = nil)
      raise BadRequestError, "Must specify an id for Reconfiguring a #{type} resource" unless id

      api_action(type, id) do |klass|
        service_dialog = resource_search(id, type, klass)
        api_log_info("Refreshing Dialog Fields for #{service_dialog_ident(service_dialog)}")

        refresh_dialog_fields_service_dialog(service_dialog, data)
      end
    end

    def fetch_service_dialogs_content(resource)
      target, resource_action = validate_dialog_content_params
      resource.content(target, resource_action, true)
    end

    def create_resource(_type, _id, data)
      dialog = DialogImportService.new.import(data)
      fetch_service_dialogs_content(dialog).first
    rescue => e
      raise BadRequestError, "Failed to create a new dialog - #{e}"
    end

    def edit_resource(type, id, data)
      service_dialog = resource_search(id, type, Dialog)
      begin
        service_dialog.update!(data.except('content'))
        service_dialog.update_tabs(data['content']['dialog_tabs']) if data['content']
      rescue => err
        raise BadRequestError, "Failed to update service dialog - #{err}"
      end
      fetch_service_dialogs_content(service_dialog).first
    end

    def copy_resource(type, id, data)
      service_dialog = resource_search(id, type, Dialog)
      attributes = data.dup
      attributes['label'] = "Copy of #{service_dialog.label}" unless attributes.key?('label')
      service_dialog.deep_copy(attributes).tap(&:save!)
    rescue => err
      raise BadRequestError, "Failed to copy service dialog - #{err}"
    end

    private

    def validate_dialog_content_params
      return unless CONTENT_PARAMS.detect { |param| params.include?(param) }
      raise BadRequestError, "Must specify all of #{CONTENT_PARAMS.join(',')}" unless (CONTENT_PARAMS - params.keys).count.zero?
      target_type = params['target_type'].pluralize.to_sym
      target = resource_search(params['target_id'], target_type, collection_class(target_type))
      resource_action = resource_search(params['resource_action_id'], :resource_actions, ResourceAction)
      [target, resource_action]
    end

    def set_additional_attributes
      @additional_attributes = %w(content) if attribute_selection == "all"
    end

    def refresh_dialog_fields_service_dialog(service_dialog, data)
      data ||= {}
      dialog_fields = Hash(data["dialog_fields"])
      refresh_fields = data["fields"]
      return action_result(false, "Must specify fields to refresh") if refresh_fields.blank?

      define_service_dialog_fields(service_dialog, dialog_fields)

      refresh_dialog_fields_action(service_dialog, refresh_fields, service_dialog_ident(service_dialog))
    rescue => err
      action_result(false, err.to_s)
    end

    def define_service_dialog_fields(service_dialog, dialog_fields)
      ident = service_dialog_ident(service_dialog)
      dialog_fields.each do |key, value|
        dialog_field = service_dialog.field(key)
        raise BadRequestError, "Dialog field #{key} specified does not exist in #{ident}" if dialog_field.nil?
        dialog_field.value = value
      end
    end

    def service_dialog_ident(service_dialog)
      "Service Dialog id:#{service_dialog.id} label:'#{service_dialog.label}'"
    end
  end
end
