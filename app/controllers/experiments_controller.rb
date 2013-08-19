class ExperimentsController < ApplicationController

  before_filter :load_experiment

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
