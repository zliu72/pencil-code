
def group(simulations, groupby, sort=True, only_started=False):
  """Group simulation by a quantity. Each Simulation object can only be part of one group.

  Args:
    simulations:    put here a Simulations object or a list of simulations [sim1, sim2, ...]
    groupby:        put here the heyword after which the grouping shall happen
    sort:           set True to sort returned dictionary naturally
    only_started:   only group simulations that already has started

  Return:
    a dictionary with keywords are the group entries and values are lists of simulations in that group
  """

  from collections import OrderedDict
  from pencilnew.math import natural_sort

  sim_dict_grouped = {}

  if type(simulations) == type(['list']):
      sim_list = simulations
  #elif type(simulations) == Simulations:
#      sim_list = simulations.sims
  else:
      print('!! ERROR: Dont know how to interprated simulations argument..')
      return False

  # sort out simulations that has not started
  if only_started == True: sim_list = [s for s in sim_list if s.started()]

  # case the groupby-keyword can be found via __simulation__.get_value
  if sim_list[0].get_value(groupby) != None:
    for sim in sim_list:
      q = str(sim.get_value(groupby))
      if (not q in sim_dict_grouped.keys()):
        sim_dict_grouped[q] = [sim]
      else:
        sim_dict_grouped[q].append(sim)

  # special cases:
  elif groupby in ['Lx', 'Ly', 'Lz']:
    for sim in sim_list:
      q = str(sim.param['lxyz'][0])
      if (not q in sim_dict_grouped.keys()):
        sim_dict_grouped[q] = [sim]
      else:
        sim_dict_grouped[q].append(sim)

  else:
    print('!! ERROR: Coudnt group simulations, no fitting groupby-keyword has been found to match "'+groupby+'"!')
    return False

  if sort:
    sim_dict_grouped_n_sorted = OrderedDict()
    for key in natural_sort(sim_dict_grouped.keys()):
      sim_dict_grouped_n_sorted[key] = sim_dict_grouped[key]
    sim_dict_grouped = sim_dict_grouped_n_sorted

  return sim_dict_grouped
