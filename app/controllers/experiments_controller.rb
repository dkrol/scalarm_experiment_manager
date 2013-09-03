require 'infrastructure_facades/infrastructure_facade'

class ExperimentsController < ApplicationController

  before_filter :load_experiment, except: [:index]

  def index
    @running_experiments = @current_user.get_running_experiments.sort { |e1, e2| e2.start_at <=> e1.start_at }
    @historical_experiments = @current_user.get_historical_experiments.sort { |e1, e2| e2.end_at <=> e1.end_at }
    @simulations = @current_user.get_simulation_scenarios.sort { |s1, s2| s2.created_at <=> s1.created_at }
  end

  def show
    config = YAML.load_file(File.join(Rails.root, 'config', 'scalarm.yml'))
    information_service = InformationService.new(config['information_service_url'], config['information_service_user'], config['information_service_pass'])

    @storage_manager_url = information_service.get_list_of('storage').sample

    @error_flag = false

    begin
      if Time.now - @experiment.start_at > 30
        Thread.new do
          Rails.logger.debug("Updating all progress bars --- #{Time.now - @experiment.start_at}")
          @experiment.update_all_bars
        end
      end

    rescue Exception => e
      flash[:error] = "Problem occured during loading experiment info - #{e}"
      @error_flag = true
      #@experiment.destroy
      #flash[:notice] = 'Your experiment has been destroyed.'
      redirect_to action: :index
    end

    unless @error_flag
      @running_experiments = @current_user.get_running_experiments.sort { |e1, e2| e2.start_at <=> e1.start_at }
      @historical_experiments = @current_user.get_historical_experiments.sort { |e1, e2| e2.end_at <=> e1.end_at }
      @simulation_scenarios = @current_user.get_simulation_scenarios.sort { |s1, s2| s2.created_at <=> s1.created_at }

      @simulation_managers = {}
      InfrastructureFacade.get_registered_infrastructures.each do |infrastructure_id, infrastructure_info|
        @simulation_managers[infrastructure_id] = infrastructure_info[:facade].get_running_simulation_managers(@current_user)
      end
    end

  end

  def get_booster_dialog
    @simulation_managers, @current_states = {}, {}
    InfrastructureFacade.get_registered_infrastructures.each do |infrastructure_id, infrastructure_info|
      @simulation_managers[infrastructure_id] = infrastructure_info[:facade].get_running_simulation_managers(@current_user)
      @current_states[infrastructure_id] = infrastructure_info[:facade].current_state(@current_user)
    end

    render inline: render_to_string(partial: 'booster_dialog')
  end

  # stops the currently running DF experiment (if any)
  def stop
    @experiment.is_running = false
    @experiment.end_at = Time.now

    @experiment.save_and_cache

    redirect_to action: :index
  end

  def file_with_configurations
    file_path = "/tmp/configurations_#{@experiment.id}.txt"
    File.delete(file_path) if File.exist?(file_path)

    File.open(file_path, 'w') do |file|
      file.puts(@experiment.create_result_csv)
    end

    send_file(file_path, type: 'text/plain')
  end

  def start_experiment
    @simulation = if params['simulation_id']
                    Simulation.find_by_id params['simulation_id']
                  elsif params['simulation_name']
                    Simulation.find_by_name params['simulation_name']
                  else
                    nil
                  end

    doe_info = if params.include?('doe')
                 JSON.parse(params['doe']).delete_if { |doe_id, parameter_list| parameter_list.first.nil? }
               else
                 []
               end

    @experiment_input = DataFarmingExperiment.prepare_experiment_input(@simulation, JSON.parse(params['experiment_input']), doe_info)
    # prepare scenario parametrization in the old fashion
    @scenario_parametrization = {}
    @experiment_input.each do |entity_group|
      entity_group['entities'].each do |entity|
        entity['parameters'].each do |parameter|
          parameter_uid = DataFarmingExperiment.parameter_uid(entity_group, entity, parameter)
          @scenario_parametrization[parameter_uid] = parameter['parametrizationType']
        end
      end
    end

    # create the new type of experiment object
    data_farming_experiment = DataFarmingExperiment.new({'simulation_id' => @simulation.id,
                                                         'experiment_input' => @experiment_input,
                                                         'name' => @simulation.name,
                                                         'is_running' => true,
                                                         'run_counter' => 1,
                                                         'time_constraint_in_sec' => 3600,
                                                         'doe_info' => doe_info,
                                                         'start_at' => Time.now,
                                                         'user_id' => @current_user.id,
                                                         'scheduling_policy' => 'monte_carlo'
                                                        })

    data_farming_experiment.user_id = @current_user.id unless @current_user.nil?
    data_farming_experiment.labels = data_farming_experiment.parameters.flatten.join(',')
    data_farming_experiment.save
    data_farming_experiment.experiment_id = data_farming_experiment.id
    data_farming_experiment.save
    # create progress bar
    data_farming_experiment.insert_initial_bar
    data_farming_experiment.create_simulation_table

    if params.include?(:computing_power) and (not params[:computing_power].empty?)
      computing_power = JSON.parse(params[:computing_power])
      InfrastructureFacade.schedule_simulation_managers(@current_user, data_farming_experiment.id, computing_power['type'], computing_power['resource_counter'])
    end

    respond_to do |format|
      format.html { redirect_to experiment_path(data_farming_experiment.id) }
      format.json { render :json => {status: 'ok', experiment_id: data_farming_experiment.id} }
    end
  end

  def calculate_experiment_size
    @simulation = if params['simulation_id']
                    Simulation.find_by_id params['simulation_id']
                  elsif params['simulation_name']
                    Simulation.find_by_name params['simulation_name']
                  else
                    nil
                  end

    doe_info = JSON.parse(params['doe']).delete_if { |doe_id, parameter_list| parameter_list.first.nil? }
    @experiment_input = DataFarmingExperiment.prepare_experiment_input(@simulation, JSON.parse(params['experiment_input']), doe_info)

    # create the new type of experiment object
    data_farming_experiment = DataFarmingExperiment.new({'simulation_id' => @simulation.id,
                                                         'experiment_input' => @experiment_input,
                                                         'name' => @simulation.name,
                                                         'is_running' => true,
                                                         'run_counter' => 1,
                                                         'time_constraint_in_sec' => 3600,
                                                         'doe_info' => doe_info
                                                        })

    experiment_size = data_farming_experiment.value_list.reduce(1) { |acc, x| acc * x.size }
    Rails.logger.debug("Experiment size is #{experiment_size}")

    render :json => {experiment_size: experiment_size}
  end

  ### Progress monitoring API

  def completed_simulations_count
    simulation_counter = @experiment.completed_simulations_count_for(params[:secs].to_i)

    render json: {count: simulation_counter}
  end

  def experiment_stats
    sims_generated, sims_sent, sims_done = @experiment.get_statistics

    if sims_generated > @experiment.experiment_size
      @experiment.experiment_size = generated
      @experiment.save
    end

    stats = {
        all: @experiment.experiment_size, sent: sims_sent, done_num: sims_done,
        done_percentage: "'%.2f'" % ((sims_done.to_f / @experiment.experiment_size) * 100),
        generated: [sims_generated, @experiment.experiment_size].min,
        progress_bar: "[#{@experiment.progress_bar_color.join(',')}]"
    }

    # TODO - mean execution time and predicted time to finish the experiment
    #if instances_done > 0 and (instances_done % 3 == 0 or instances_done == experiment.experiment_size)
    #  ei_perform_time_avg = ExperimentInstance.get_avg_execution_time_of_ei(experiment.id)
    #  ei_perform_time_avg_m = (ei_perform_time_avg / 60.to_f).floor
    #  ei_perform_time_avg_s = (ei_perform_time_avg - ei_perform_time_avg_m*60).to_i
    #
    #  ei_perform_time_avg = ''
    #  ei_perform_time_avg += "#{ei_perform_time_avg_m} minutes"  if ei_perform_time_avg_m > 0
    #  ei_perform_time_avg += ' and ' if (ei_perform_time_avg_m > 0) and (ei_perform_time_avg_s > 0)
    #  ei_perform_time_avg +=  "#{ei_perform_time_avg_s} seconds" if ei_perform_time_avg_s > 0
    #
    #  # ei_perform_time_avg = "%.2f" % ei_perform_time_avg
    #  partial_stats['avg_simulation_time'] = ei_perform_time_avg
    #
    #  predicted_finish_time = (Time.now - experiment.start_at).to_f / 3600
    #  predicted_finish_time /= (instances_done.to_f / experiment.experiment_size)
    #  predicted_finish_time_h = predicted_finish_time.floor
    #  predicted_finish_time_m = ((predicted_finish_time.to_f - predicted_finish_time_h.to_f)*60).to_i
    #
    #  predicted_finish_time = ''
    #  predicted_finish_time += "#{predicted_finish_time_h} hours"  if predicted_finish_time_h > 0
    #  predicted_finish_time += ' and ' if (predicted_finish_time_h > 0) and (predicted_finish_time_m > 0)
    #  predicted_finish_time +=  "#{predicted_finish_time_m} minutes" if predicted_finish_time_m > 0
    #
    #  partial_stats["predicted_finish_time"] = predicted_finish_time
    #end

    render json: stats
  end

  def experiment_moes
    moes_info = {}

    moes = @experiment.result_names
    moes = moes.nil? ? ['No MoEs found', 'nil'] : moes.map { |x| [DataFarmingExperiment.output_parameter_label_for(x), x] }

    done_instance = @experiment.find_simulation_docs_by({'is_done' => true}, {limit: 1, fields: %w(arguments)}).first

    moes_and_params = if done_instance.nil?
                        ['No input parameters found', 'nil']
                      else
                        moes + [%w(----------- nil)] +
                            done_instance['arguments'].split(',').map { |x| [@experiment.input_parameter_label_for(x), x] }
                      end

    moes_info[:moes] = moes.map { |label, id| "<option value='#{id}'>#{label}</option>" }.join()
    moes_info[:moes_and_params] = moes_and_params.map { |label, id| "<option value='#{id}'>#{label}</option>" }.join()

    render :json => moes_info
  end

  #  getting parametrization and generated values of every input parameter without default value
  def extension_dialog
    @parameters = {}

    @experiment.parameters.flatten.each do |parameter_uid|
      parameter_doc = @experiment.get_parameter_doc(parameter_uid)
      next if parameter_doc['with_default_value'] # it means this parameter has only one possible value - the default one
      parameter_info = {}
      parameter_info[:label] = @experiment.input_parameter_label_for(parameter_uid)
      parameter_info[:parametrizationType] = parameter_doc['parametrizationType']
      parameter_info[:in_doe] = parameter_doc['in_doe']
      parameter_info[:values] = @experiment.parameter_values_for(parameter_uid)

      @parameters[parameter_uid] = parameter_info
    end

    Rails.logger.debug("Parameters: #{@parameters}")

    render partial: 'extension_dialog'
  end

  def extend_input_values
    parameter_uid = params[:param_name]
    @range_min, @range_max, @range_step = params[:range_min].to_f, params[:range_max].to_f, params[:range_step].to_f
    Rails.logger.debug("New range values: #{@range_min} --- #{@range_max} --- #{@range_step}")
    new_parameter_values = @range_min.step(@range_max, @range_step).to_a
    #@priority = params[:priority].to_i
    Rails.logger.debug("New parameter values: #{new_parameter_values}")

    @num_of_new_simulations = @experiment.add_parameter_values(parameter_uid, new_parameter_values)
    if @num_of_new_simulations > 0
      @experiment.create_progress_bar_table.drop
      @experiment.insert_initial_bar

      # 4. update progress bar
      Thread.new do
        Rails.logger.debug("Updating all progress bars --- #{Time.now - @experiment.start_at}")
        @experiment.update_all_bars
      end
    end

  end

  def running_simulations_table
  end

  def completed_simulations_table
  end

  def intermediate_results
    unless @experiment.parameters.blank?
      arguments = @experiment.parameters.flatten

      results = if params[:simulations] == 'running'
                  @experiment.find_simulation_docs_by({to_sent: false, is_done: false})
                  #ExperimentInstance.find_by_query(@experiment.experiment_id, {'to_sent' => false, 'is_done' => false})
                elsif params[:simulations] == 'completed'
                  @experiment.find_simulation_docs_by({is_done: true})
                  #ExperimentInstance.find_by_query(@experiment.experiment_id, {'is_done' => true})
                end

      result_column = if params[:simulations] == 'running'
                        'tmp_result'
                      elsif params[:simulations] == 'completed'
                        'result'
                      end

      results = results.map{ |simulation|
        split_values = simulation['values'].split(',')
        modified_values = @experiment.range_arguments.reduce([]){|acc, param_uid| acc << split_values[arguments.index(param_uid)]}
        time_column = if params[:simulations] == 'running'
                        simulation['sent_at'].strftime('%Y-%m-%d %H:%M')
                              elsif params[:simulations] == 'completed'
                                "#{simulation['done_at'] - simulation['sent_at']} [s]"
                              end

        [
            simulation['id'],
            time_column,
            simulation[result_column].to_s || 'No data available',
            modified_values
        ].flatten
      }

      render json: { 'aaData' => results }.as_json
    else
      render json: { 'aaData' => [] }.as_json
    end
  end

  def change_scheduling_policy
    new_scheduling_policy = params[:scheduling_policy]

    @experiment.scheduling_policy = new_scheduling_policy
    msg = if @experiment.save_and_cache
      'The scheduling policy of the experiment has been changed.'
    else
      'The scheduling policy of the experiment could not have been changed due to internal server issues.'
    end

    respond_to do |format|
      format.js {
        render :inline => "
          $('#scheduling-busy').hide();
          $('#scheduling-ajax-response').html('#{msg}');
          $('#policy_name').html('#{new_scheduling_policy}');
        "
      }
    end
  end

  def destroy
    unless @experiment.nil?
      @experiment.destroy
      flash[:notice] = 'Your experiment has been destroyed.'
    else
      flash[:notice] = 'Your experiment is no longer available.'
    end

    redirect_to :action => :index
  end

  private

  def load_experiment
    #Rails.logger.debug("Loading experiment --- #{params.include?('id')} --- #{@current_user.nil?}")
    if params.include?('id') and not @current_user.nil?
      @experiment = DataFarmingExperiment.find_by_query({'user_id' => @current_user.id, '_id' => BSON::ObjectId(params['id'])})

      if @experiment.nil?
        flash[:error] = "Experiment '#{params['id']}' for user '#{@current_user.login}' not found"

        redirect action: :index
      end
    end
  end

end
