class ExperimentsController < ApplicationController

  ### Progress monitoring API

  def completed_simulations_count
    experiment = DataFarmingExperiment.find_by_id(params[:id])

    simulation_counter = if experiment
                experiment.completed_simulations_count_for(params[:secs].to_i)
              else
                0
              end

    render json: { count: simulation_counter }
  end

end
