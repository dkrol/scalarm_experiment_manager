# job1 = fork {
	# Start experiment watcher
	ExperimentWatcher.watch_experiments
	# sleep(10) while true
# }
# Process.detach(job1)

# job2 = fork {
	# Start infrastructure Monitoring
	InfrastructureFacade.start_monitoring
	# sleep(10) while true
# }
# Process.detach(job2)
