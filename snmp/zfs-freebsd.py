#!/usr/local/bin/python3

# FreeNAS 11.1 not support #!/usr/bin/env python3

import json
import subprocess

def percent(numerator, denominator, default=0):
	try:
		return numerator / denominator * 100
	except ZeroDivisionError:
		return default

def main(args):
	p = subprocess.run(['/sbin/sysctl', '-q', 'kstat.zfs', 'vfs.zfs'], stdout=subprocess.PIPE, universal_newlines=True)
	
	if p.returncode != 0:
		return p.returncode

	def chomp(line):
		bits = [b.strip() for b in line.split(':')]
		return bits[0], int(bits[1])
	stats = dict(chomp(l) for l in p.stdout.splitlines())
	if 'kstat.zfs.misc.arcstats.recycle_miss' not in stats:
		stats['kstat.zfs.misc.arcstats.recycle_miss'] = 0

	output = dict()

	# ARC misc
	output['deleted'] = stats['kstat.zfs.misc.arcstats.deleted']
	output['evict_skip'] = stats['kstat.zfs.misc.arcstats.evict_skip']
	output['mutex_skip'] = stats['kstat.zfs.misc.arcstats.mutex_miss']
	output['recycle_miss'] = stats['kstat.zfs.misc.arcstats.recycle_miss']

	# ARC size
	output['target_size_per'] = stats['kstat.zfs.misc.arcstats.c'] / stats['kstat.zfs.misc.arcstats.c_max'] * 100
	output['arc_size_per'] = stats['kstat.zfs.misc.arcstats.size'] / stats['kstat.zfs.misc.arcstats.c_max'] * 100
	output['target_size_arat'] = stats['kstat.zfs.misc.arcstats.c'] / stats['kstat.zfs.misc.arcstats.c_max']
	output['min_size_per'] = stats['kstat.zfs.misc.arcstats.c_min'] / stats['kstat.zfs.misc.arcstats.c_max'] * 100

	output['arc_size'] = stats['kstat.zfs.misc.arcstats.size']
	output['target_size_max'] = stats['kstat.zfs.misc.arcstats.c_max']
	output['target_size_min'] = stats['kstat.zfs.misc.arcstats.c_min']
	output['target_size'] = stats['kstat.zfs.misc.arcstats.c']

	# ARC size breakdown
	output['mfu_size'] = stats['kstat.zfs.misc.arcstats.size'] - stats['kstat.zfs.misc.arcstats.p']
	output['p'] = stats['kstat.zfs.misc.arcstats.p']
	output['rec_used_per'] = stats['kstat.zfs.misc.arcstats.p'] / stats['kstat.zfs.misc.arcstats.size'] * 100
	output['freq_used_per'] = output['mfu_size'] / stats['kstat.zfs.misc.arcstats.size'] * 100

	# ARC misc efficiency stats
	output['arc_hits'] = stats['kstat.zfs.misc.arcstats.hits']
	output['arc_misses'] = stats['kstat.zfs.misc.arcstats.misses']
	output['demand_data_hits'] = stats['kstat.zfs.misc.arcstats.demand_data_hits']
	output['demand_data_misses'] = stats['kstat.zfs.misc.arcstats.demand_data_misses']
	output['demand_meta_hits'] = stats['kstat.zfs.misc.arcstats.demand_metadata_hits']
	output['demand_meta_misses'] = stats['kstat.zfs.misc.arcstats.demand_metadata_misses']
	output['mfu_ghost_hits'] = stats['kstat.zfs.misc.arcstats.mfu_ghost_hits']
	output['mfu_hits'] = stats['kstat.zfs.misc.arcstats.mfu_hits']
	output['mru_ghost_hits'] = stats['kstat.zfs.misc.arcstats.mru_ghost_hits']
	output['mru_hits'] = stats['kstat.zfs.misc.arcstats.mru_hits']
	output['pre_data_hits'] = stats['kstat.zfs.misc.arcstats.prefetch_data_hits']
	output['pre_data_misses'] = stats['kstat.zfs.misc.arcstats.prefetch_data_misses']
	output['pre_meta_hits'] = stats['kstat.zfs.misc.arcstats.prefetch_metadata_hits']
	output['pre_meta_misses'] = stats['kstat.zfs.misc.arcstats.prefetch_metadata_misses']

	output['anon_hits'] = output['arc_hits'] - (output['mfu_hits'] + output['mru_hits'] + output['mfu_ghost_hits'] + output['mru_ghost_hits'])
	output['arc_accesses_total'] = output['arc_hits'] + output['arc_misses']
	output['demand_data_total'] = output['demand_data_hits'] + output['demand_data_misses']
	output['pre_data_total'] = output['pre_data_hits'] + output['pre_data_misses']
	output['real_hits'] = output['mfu_hits'] + output['mru_hits']

	# ARC efficiency percents
	output['cache_hits_per'] = percent(output['arc_hits'], output['arc_accesses_total'])
	output['cache_miss_per'] = percent(output['arc_misses'], output['arc_accesses_total'])
	output['actual_hit_per'] = percent(output['real_hits'], output['arc_accesses_total'])
	output['data_demand_per'] = percent(output['demand_data_hits'], output['demand_data_total'])
	output['data_pre_per'] = percent(output['pre_data_hits'], output['pre_data_total'])
	output['anon_hits_per'] = percent(output['anon_hits'], output['arc_hits'])
	output['mru_per'] = percent(output['mru_hits'], output['arc_hits'])
	output['mfu_per'] = percent(output['mfu_hits'], output['arc_hits'])
	output['mru_ghost_per'] = percent(output['mru_ghost_hits'], output['arc_hits'])
	output['mfu_ghost_per'] = percent(output['mfu_ghost_hits'], output['arc_hits'])
	output['demand_hits_per'] = percent(output['demand_data_hits'], output['arc_hits'])
	output['pre_hits_per'] = percent(output['pre_data_hits'], output['arc_hits'])
	output['meta_hits_per'] = percent(output['demand_meta_hits'], output['arc_hits'])
	output['pre_meta_hits_per'] = percent(output['pre_meta_hits'], output['arc_hits'])
	output['demand_misses_per'] = percent(output['demand_data_misses'], output['arc_misses'])
	output['pre_misses_per'] = percent(output['pre_data_misses'], output['arc_misses'])
	output['meta_misses_per'] = percent(output['demand_meta_misses'], output['arc_misses'])
	output['pre_meta_misses_per'] = percent(output['pre_meta_misses'], output['arc_misses'])

	# pools
	p = subprocess.run(['/sbin/zpool', 'list', '-pH'], stdout=subprocess.PIPE, universal_newlines=True)
	if p.returncode != 0:
		return p.returncode
	output['pools'] = []
	fields = ['name', 'size', 'alloc', 'free', 'ckpoint', 'expandsz', 'frag', 'cap', 'dedup']
	for l in p.stdout.splitlines():
		p = dict(zip(fields, l.split('\t')))
		if p['ckpoint'] == '-': 
			p['ckpoint'] = 0 
		if p['expandsz'] == '-':
			p['expandsz'] = 0
		p['frag'] = p['frag'].rstrip('%')
		if p['frag'] == '-':
			p['frag'] = 0
		p['cap'] = p['cap'].rstrip('%')
		if p['cap'] == '-':
			p['cap'] = 0
		p['dedup'] = p['dedup'].rstrip('x')
		output['pools'].append(p)

	print(json.dumps(output))

	return 0

if __name__ == '__main__':
	import sys
	sys.exit(main(sys.argv[1:]))
