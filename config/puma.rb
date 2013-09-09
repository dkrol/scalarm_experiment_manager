environment 'production'
daemonize

bind 'unix:///tmp/scalarm_experiment_manager.sock'
#bind 'tcp://0.0.0.0:3000'

#activate_control_app 'tcp://0.0.0.0:4000', { no_token: true }
pidfile 'puma.pid'

threads 1,16
workers 4
preload_app!