module SimulationsHelper

  def select_doe_type
    options_for_select([
                           ['Near Orthogonal Latin Hypercubes', 'nolhDesign'],
                           ['2^k', '2k'],
                           ['Full factorial', 'fullFactorial'],
                           ['Fractional factorial (with Federov algorithm)', 'fractionalFactorial'],
                           ['Orthogonal Latin Hypercubes', 'latinHypercube'],
                       ])
  end

end
