class ExperimentsController < ApplicationController

  before_filter :load_experiment

  ### Progress monitoring API

  def completed_simulations_count
    simulation_counter = @experiment.completed_simulations_count_for(params[:secs].to_i)

    render json: { count: simulation_counter }
  end

  def experiment_stats
    generated, sent, done_num = @experiment.get_statistics
    if generated > @experiment.experiment_size
      @experiment.experiment_size = generated
      @experiment.save
    end

    stats = {
      all: @experiment.experiment_size, sent: instances_sent, done_num: instances_done,
      done_percentage: "'%.2f'" % ((instances_done.to_f / @experiment.experiment_size) * 100),
      generated: [generated, @experiment.experiment_size].min,
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
