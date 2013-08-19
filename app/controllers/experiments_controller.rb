class ExperimentsController < ApplicationController

  before_filter :load_experiment

  ### Progress monitoring API

  def completed_simulations_count
    simulation_counter = @experiment.completed_simulations_count_for(params[:secs].to_i)

    render json: { count: simulation_counter }
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
