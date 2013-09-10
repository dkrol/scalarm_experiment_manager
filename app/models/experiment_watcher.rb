class ExperimentWatcher

  def self.watch_experiments
    Rails.logger.debug('[experiment_watcher] Watch experiments')

    Thread.new do
      while true do
        Rails.logger.debug("[experiment_watcher] #{Time.now} --- running")
        DataFarmingExperiment.get_running_experiments.each do |experiment|
          Rails.logger.debug("Experiment: #{experiment}")
          begin
            experiment.find_simulation_docs_by({is_done: false, to_sent: false}).each do |simulation|
              Rails.logger.debug("#{Time.now - simulation['sent_at']} ? #{experiment.time_constraint_in_sec * 2}")
              if Time.now - simulation['sent_at'] >= experiment.time_constraint_in_sec * 2
                simulation['to_sent'] = true
                experiment.progress_bar_update(simulation['id'], 'rollback')
                experiment.save_simulation(simulation)
              end
            end
          rescue Exception => e
            Rails.logger.debug("Error during experiment watching #{e}")
          end
        end

        sleep(600)
      end
    end
  end

end
