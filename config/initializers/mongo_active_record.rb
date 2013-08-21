require 'information_service'

config = YAML.load_file(File.join(Rails.root, 'config', 'scalarm.yml'))
information_service = InformationService.new(config['information_service_url'], config['information_service_user'], config['information_service_pass'])
storage_manager_list = information_service.get_list_of('db_routers')

MongoActiveRecord.connection_init(storage_manager_list.sample, config['db_name'])
