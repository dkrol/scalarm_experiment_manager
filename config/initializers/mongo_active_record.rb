require 'information_service'
#require 'mongo_active_record'

config = YAML.load_file(File.join(Rails.root, 'config', 'scalarm.yml'))
#information_service = InformationService.new(config['information_service_url'], config['information_service_user'], config['information_service_pass'])

#storage_manager_list = information_service.get_list_of('storage')

MongoActiveRecord.connection_init('localhost:27017', config['db_name'])
