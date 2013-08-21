class ExperimentsController < ApplicationController

  before_filter :load_experiment, except: [ :index ]

  def index
    @running_experiments = @current_user.get_running_experiments.sort { |e1, e2| e2.start_at <=> e1.start_at }
    @historical_experiments = @current_user.get_historical_experiments.sort { |e1, e2| e2.end_at <=> e1.end_at }
    @simulations = @current_user.get_simulation_scenarios.sort { |s1, s2| s2.created_at <=> s1.created_at }
  end

  def show

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

    # create the old fashion experiment object
    #@experiment = Experiment.new(:is_running => true,
    #                             :instance_index => 0,
    #                             :run_counter => 1,
    #                             :time_constraint_in_sec => 60,
    #                             :time_constraint_in_iter => 100,
    #                             :experiment_name => @simulation.name,
    #                             :parametrization => @scenario_parametrization.map { |k, v| "#{k}=#{v}" }.join(','))

    #@experiment.save_and_cache
    # create the new type of experiment object
    data_farming_experiment = DataFarmingExperiment.new({#'experiment_id' => @experiment.id,
                                                         'simulation_id' => @simulation.id,
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
    # rewrite all necessary parameters
    #@experiment.parameters = data_farming_experiment.parametrization_values
    #@experiment.arguments = data_farming_experiment.parametrization_values
    #@experiment.doe_groups = ''
    #@experiment.experiment_size = data_farming_experiment.experiment_size
    #@experiment.is_running = true
    #@experiment.start_at = Time.now
    # create progress bar
    data_farming_experiment.insert_initial_bar
    data_farming_experiment.create_simulation_table
    # DEPRECATED
    # create multiple list to fast generete subsequent simulations
    #labels = data_farming_experiment.parameters
    #value_list = data_farming_experiment.value_list
    #multiply_list = data_farming_experiment.multiply_list
    #ExperimentInstanceDb.default_instance.store_experiment_info(@experiment, labels, value_list, multiply_list)
    #@experiment.save_and_cache

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

    render :json => { experiment_size: experiment_size }
  end

  ### Progress monitoring API

  def completed_simulations_count
    simulation_counter = @experiment.completed_simulations_count_for(params[:secs].to_i)

    render json: { count: simulation_counter }
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

    done_instance = @experiment.find_simulations_by({'is_done' => true}, {limit: 1}).first

    moes_and_params = if done_instance.nil?
                        ['No input parameters found', 'nil']
                      else
                        moes + [%w(----------- nil)] +
                            done_instance.arguments.split(',').map { |x| [@experiment.input_parameter_label_for(x), x] }
                      end

    moes_info[:moes] = moes.map { |label, id| "<option value='#{id}'>#{label}</option>" }.join()
    moes_info[:moes_and_params] = moes_and_params.map { |label, id| "<option value='#{id}'>#{label}</option>" }.join()

    render :json => moes_info
  end

  private

  def load_experiment
    #Rails.logger.debug("Loading experiment --- #{params.include?('id')} --- #{@current_user.nil?}")
    if params.include?('id') and not @current_user.nil?
      @experiment = DataFarmingExperiment.find_by_query({ 'user_id' => @current_user.id, '_id' => BSON::ObjectId(params['id']) })
      #Rails.logger.debug("Experiment: #{@experiment}")
      if @experiment.nil?
        raise "Experiment '#{params['id']}' for user '#{@current_user.login}' not found"
      end
    end
  end

end
