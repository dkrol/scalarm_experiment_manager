module ExperimentsHelper

  def select_scheduling_policy
      select_tag 'scheduling_policy', options_for_select([
        ['Monte Carlo', 'monte_carlo'],
        ['Sequential forward', 'sequential_forward'],
        ['Sequential backward', 'sequential_backward']])
  end

end
