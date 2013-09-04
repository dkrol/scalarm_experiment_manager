require 'simulation'

class SimulationsController < ApplicationController
  before_filter :load_simulation, only: [:show, :progress_info, :mark_as_complete]

  def index
    @simulations = @current_user.get_simulation_scenarios
    @simulation_scenarios = @simulations
    @input_writers = SimulationInputWriter.find_all_by_user_id(@current_user.id)
    @executors = SimulationExecutor.find_all_by_user_id(@current_user.id)
    @output_readers = SimulationOutputReader.find_all_by_user_id(@current_user.id)
    @progress_monitors = SimulationProgressMonitor.find_all_by_user_id(@current_user.id)
  end

  def registration
  end

  def upload_component
    if params['component_type'] == 'input_writer'
      input_writer = SimulationInputWriter.new({name: params['component_name'], code: params['component_code'].read, user_id: @current_user.id})
      input_writer.save
    elsif params['component_type'] == 'executor'
      executor = SimulationExecutor.new({name: params['component_name'], code: params['component_code'].read, user_id: @current_user.id})
      executor.save
    elsif params['component_type'] == 'output_reader'
      output_reader = SimulationOutputReader.new({name: params['component_name'], code: params['component_code'].read, user_id: @current_user.id})
      output_reader.save
    elsif params['component_type'] == 'progress_monitor'
      progress_monitor = SimulationProgressMonitor.new({name: params['component_name'], code: params['component_code'].read, user_id: @current_user.id})
      progress_monitor.save
    end

    redirect_to :action => :index
  end

  def destroy_component
    if params['component_type'] == 'input_writer'
      SimulationInputWriter.find_by_id(params['component_id']).destroy
    elsif params['component_type'] == 'executor'
      SimulationExecutor.find_by_id(params['component_id']).destroy
    elsif params['component_type'] == 'output_reader'
      SimulationOutputReader.find_by_id(params['component_id']).destroy
    elsif params['component_type'] == 'progress_monitor'
      SimulationProgressMonitor.find_by_id(params['component_id']).destroy
    end

    redirect_to :action => :index
  end

  def upload_simulation
    simulation = Simulation.new({
        'input_writer_id' => params['input_writer_id'],
        'executor_id' => params['executor_id'],
        'output_reader_id' => params['output_reader_id'],
        'name' => params['simulation_name'],
        'description' => params['simulation_description'],
        'input_specification' => params['simulation_input'].read,
        'user_id' => @current_user.id,
        'created_at' => Time.now
                   })

    simulation.progress_monitor_id = params['progress_monitor_id'] if params['progress_monitor_id']
    simulation.set_simulation_binaries(params['simulation_binaries'].original_filename, params['simulation_binaries'].read)

    simulation.save

    redirect_to :action => :index
  end

  def destroy_simulation
    Simulation.find_by_id(params['component_id']).destroy
    redirect_to :action => :index
  end

  # following methods are used in experiment conducting
  require 'json'

  def conduct_experiment
    @simulation = Simulation.find_by_id(params[:simulation_id])
    @simulation_input = JSON.parse(@simulation.input_specification)
  end



  # a life-cycle of a single simulation

  def mark_as_complete
    response = { status: 'ok' }

    begin
      if @simulation.nil? or @simulation['is_done']
        logger.debug("Experiment Instance #{params[:id]} of experiment #{params[:experiment_id]} is already done or is nil? #{@simulation.nil?}")
      else
        @simulation['is_done'] = true
        @simulation['to_sent'] = false
        @simulation['result'] = JSON.parse(params[:result])
        @simulation['done_at'] = Time.now
        @experiment.save_simulation(@simulation)
        # TODO adding caching capability
        #@simulation.remove_from_cache

        @experiment.progress_bar_update(@simulation['id'], 'done')
      end
    rescue Exception => e
      Rails.logger.debug("Error in marking a simulation as complete - #{e}")
      response = { status: 'error', reason: e.to_s }
    end

    render :json => response
  end

  def progress_info
    response = {status: 'ok'}

    begin
      if @simulation.nil? or @simulation['is_done']
        logger.debug("Simulation #{params[:id]} of experiment #{params[:experiment_id]} is already done or is nil? #{@simulation.nil?}")
      else
        @simulation['tmp_result'] = JSON.parse(params[:result])
        @experiment.save_simulation(@simulation)
      end
    rescue Exception => e
      Rails.logger.debug("Error in the 'progress_info' function - #{e}")
      response = {status: 'error', reason: e.to_s}
    end

    render :json => response
  end

  def show
    if @simulation.nil?
      @simulation = @experiment.generate_simulation_for(params[:id].to_i)
      @experiment.save_simulation(@simulation)
    end

    render partial: 'show'
  end

  private

  def load_simulation
    @experiment = DataFarmingExperiment.find_by_id(params[:experiment_id])
    #Rails.logger.debug("Experiment: #{@experiment}")
    @simulation = @experiment.find_simulation_docs_by({id: params[:id].to_i}, {limit: 1}).first
    #Rails.logger.debug("Simulation: #{@simulation}")
  end

end
