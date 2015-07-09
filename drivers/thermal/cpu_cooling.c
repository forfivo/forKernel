/*
 *  linux/drivers/thermal/cpu_cooling.c
 *
 *  Copyright (C) 2012	Samsung Electronics Co., Ltd(http://www.samsung.com)
 *  Copyright (C) 2012  Amit Daniel <amit.kachhap@linaro.org>
 *
 * ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; version 2 of the License.
 *
 *  This program is distributed in the hope that it will be useful, but
 *  WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along
 *  with this program; if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA 02111-1307 USA.
 *
 * ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 */
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/thermal.h>
#include <linux/platform_device.h>
#include <linux/cpufreq.h>
#include <linux/err.h>
#include <linux/slab.h>
#include <linux/cpu.h>
#include <linux/cpu_cooling.h>

/**
 * struct cpufreq_cooling_device
 * @id: unique integer value corresponding to each cpufreq_cooling_device
 *	registered.
 * @cool_dev: thermal_cooling_device pointer to keep track of the the
 *	egistered cooling device.
 * @tab_ptr: freq_clip_table table containing the maximum value of frequency to
 *	be set for different cooling state.
 * @tab_size: integer value representing a count of the above table.
 * @cpufreq_state: integer value representing the current state of cpufreq
 *	cooling	devices.
 * @allowed_cpus: all the cpus involved for this cpufreq_cooling_device.
 * @node: list_head to link all cpufreq_cooling_device together.
 *
 * This structure is required for keeping information of each
 * cpufreq_cooling_device registered as a list whose head is represented by
 * cooling_cpufreq_list. In order to prevent corruption of this list a
 * mutex lock cooling_cpufreq_lock is used.
 */
struct cpufreq_cooling_device {
	int id;
	struct thermal_cooling_device *cool_dev;
	struct freq_clip_table *tab_ptr;
	unsigned int tab_size;
	unsigned int cpufreq_state;
	struct cpumask allowed_cpus;
	struct list_head node;
};
static LIST_HEAD(cooling_cpufreq_list);
static DEFINE_MUTEX(cooling_cpufreq_lock);
static DEFINE_IDR(cpufreq_idr);

/*per cpu variable to store the previous max frequency allowed*/
static DEFINE_PER_CPU(unsigned int, max_policy_freq);

/*notify_table passes value to the CPUFREQ_ADJUST callback function.*/
#define NOTIFY_INVALID NULL
static struct freq_clip_table *notify_table;

/*Head of the blocking notifier chain to inform about frequency clamping*/
static BLOCKING_NOTIFIER_HEAD(cputherm_state_notifier_list);

/**
 * get_idr - function to get a unique id.
 * @idr: struct idr * handle used to create a id.
 * @id: int * value generated by this function.
 */
static int get_idr(struct idr *idr, int *id)
{
	int ret;

	mutex_lock(&cooling_cpufreq_lock);
	ret = idr_alloc(idr, NULL, 0, 0, GFP_KERNEL);
	mutex_unlock(&cooling_cpufreq_lock);
	if (unlikely(ret < 0))
		return ret;
	*id = ret;

	return 0;
}

/**
 * release_idr - function to free the unique id.
 * @idr: struct idr * handle used for creating the id.
 * @id: int value representing the unique id.
 */
static void release_idr(struct idr *idr, int id)
{
	mutex_lock(&cooling_cpufreq_lock);
	idr_remove(idr, id);
	mutex_unlock(&cooling_cpufreq_lock);
}

/**
 * cputherm_register_notifier - Register a notifier with cpu cooling interface.
 * @nb:	struct notifier_block * with callback info.
 * @list: integer value for which notification is needed. possible values are
 *	CPUFREQ_COOLING_START and CPUFREQ_COOLING_STOP.
 *
 * This exported function registers a driver with cpu cooling layer. The driver
 * will be notified when any cpu cooling action is called.
 */
int cputherm_register_notifier(struct notifier_block *nb, unsigned int list)
{
	int ret = 0;

	switch (list) {
	case CPUFREQ_COOLING_START:
	case CPUFREQ_COOLING_STOP:
		ret = blocking_notifier_chain_register(
				&cputherm_state_notifier_list, nb);
		break;
	default:
		ret = -EINVAL;
	}
	return ret;
}
EXPORT_SYMBOL(cputherm_register_notifier);

/**
 * cputherm_unregister_notifier - Un-register a notifier.
 * @nb:	struct notifier_block * with callback info.
 * @list: integer value for which notification is needed. values possible are
 *	CPUFREQ_COOLING_START or CPUFREQ_COOLING_STOP.
 *
 * This exported function un-registers a driver with cpu cooling layer.
 */
int cputherm_unregister_notifier(struct notifier_block *nb, unsigned int list)
{
	int ret = 0;

	switch (list) {
	case CPUFREQ_COOLING_START:
	case CPUFREQ_COOLING_STOP:
		ret = blocking_notifier_chain_unregister(
				&cputherm_state_notifier_list, nb);
		break;
	default:
		ret = -EINVAL;
	}
	return ret;
}
EXPORT_SYMBOL(cputherm_unregister_notifier);

/*Below codes defines functions to be used for cpufreq as cooling device*/

/**
 * is_cpufreq_valid - function to check if a cpu has frequency transition policy.
 * @cpu: cpu for which check is needed.
 */
static int is_cpufreq_valid(int cpu)
{
	struct cpufreq_policy policy;
	return !cpufreq_get_policy(&policy, cpu);
}

/**
 * cpufreq_apply_cooling - function to apply frequency clipping.
 * @cpufreq_device: cpufreq_cooling_device pointer containing frequency
 *	clipping data.
 * @cooling_state: value of the cooling state.
 */
static int cpufreq_apply_cooling(struct cpufreq_cooling_device *cpufreq_device,
				unsigned long cooling_state)
{
	unsigned int event, cpuid, state;
	struct freq_clip_table *th_table, *table_ptr;
	const struct cpumask *maskPtr = &cpufreq_device->allowed_cpus;
	struct cpufreq_cooling_device *cpufreq_ptr;

	if (cooling_state > cpufreq_device->tab_size)
		return -EINVAL;

	/*Check if the old cooling action is same as new cooling action*/
	if (cpufreq_device->cpufreq_state == cooling_state)
		return 0;

	/*pass cooling table info to the cpufreq_thermal_notifier callback*/
	notify_table = NOTIFY_INVALID;

	if (cooling_state > 0) {
		th_table = &(cpufreq_device->tab_ptr[cooling_state - 1]);
		notify_table = th_table;
	}

	/*check if any lower clip frequency active in other cpufreq_device's*/
	list_for_each_entry(cpufreq_ptr, &cooling_cpufreq_list, node) {

		state = cpufreq_ptr->cpufreq_state;
		if (state == 0 || cpufreq_ptr == cpufreq_device)
			continue;

		if (!cpumask_equal(&cpufreq_ptr->allowed_cpus,
				&cpufreq_device->allowed_cpus))
			continue;

		table_ptr = &(cpufreq_ptr->tab_ptr[state - 1]);
		if (notify_table == NULL ||
				(table_ptr->freq_clip_max <
				notify_table->freq_clip_max))
			notify_table =  table_ptr;
	}

	cpufreq_device->cpufreq_state = cooling_state;

	if (notify_table != NOTIFY_INVALID) {
		event = CPUFREQ_COOLING_START;
		maskPtr = notify_table->mask_val;
		pr_info("[TMU] COOLING START: temp_level=%d, clip_max=%d\n",
				notify_table->temp_level, notify_table->freq_clip_max);
	} else {
		event = CPUFREQ_COOLING_STOP;
		pr_info("[TMU] COOLING STOP\n");
	}

	blocking_notifier_call_chain(&cputherm_state_notifier_list,
						event, notify_table);

	for_each_cpu(cpuid, maskPtr) {
		if (is_cpufreq_valid(cpuid))
			cpufreq_update_policy(cpuid);
	}

	notify_table = NOTIFY_INVALID;

	return 0;
}

/**
 * cpufreq_thermal_notifier - notifier callback for cpufreq policy change.
 * @nb:	struct notifier_block * with callback info.
 * @event: value showing cpufreq event for which this function invoked.
 * @data: callback-specific data
 */
static int cpufreq_thermal_notifier(struct notifier_block *nb,
					unsigned long event, void *data)
{
	struct cpufreq_policy *policy = data;
	unsigned long max_freq = 0;

	if (event != CPUFREQ_ADJUST)
		return 0;

	if (notify_table != NOTIFY_INVALID) {
		max_freq = notify_table->freq_clip_max;

		if (!per_cpu(max_policy_freq, policy->cpu))
			per_cpu(max_policy_freq, policy->cpu) = policy->max;
	} else {
		if (per_cpu(max_policy_freq, policy->cpu)) {
			max_freq = per_cpu(max_policy_freq, policy->cpu);
			per_cpu(max_policy_freq, policy->cpu) = 0;
		} else {
			max_freq = policy->max;
		}
	}

	if (policy->max != max_freq)
		cpufreq_verify_within_limits(policy, 0, max_freq);

	return 0;
}

/*
 * cpufreq cooling device callback functions are defined below
 */

/**
 * cpufreq_get_max_state - callback function to get the max cooling state.
 * @cdev: thermal cooling device pointer.
 * @state: fill this variable with the max cooling state.
 */
static int cpufreq_get_max_state(struct thermal_cooling_device *cdev,
				 unsigned long *state)
{
	int ret = -EINVAL;
	struct cpufreq_cooling_device *cpufreq_device;

	mutex_lock(&cooling_cpufreq_lock);
	list_for_each_entry(cpufreq_device, &cooling_cpufreq_list, node) {
		if (cpufreq_device && cpufreq_device->cool_dev == cdev) {
			*state = cpufreq_device->tab_size;
			ret = 0;
			break;
		}
	}
	mutex_unlock(&cooling_cpufreq_lock);
	return ret;
}

/**
 * cpufreq_get_cur_state - callback function to get the current cooling state.
 * @cdev: thermal cooling device pointer.
 * @state: fill this variable with the current cooling state.
 */
static int cpufreq_get_cur_state(struct thermal_cooling_device *cdev,
				 unsigned long *state)
{
	int ret = -EINVAL;
	struct cpufreq_cooling_device *cpufreq_device;

	mutex_lock(&cooling_cpufreq_lock);
	list_for_each_entry(cpufreq_device, &cooling_cpufreq_list, node) {
		if (cpufreq_device && cpufreq_device->cool_dev == cdev) {
			*state = cpufreq_device->cpufreq_state;
			ret = 0;
			break;
		}
	}
	mutex_unlock(&cooling_cpufreq_lock);
	return ret;
}

/**
 * cpufreq_set_cur_state - callback function to set the current cooling state.
 * @cdev: thermal cooling device pointer.
 * @state: set this variable to the current cooling state.
 */
static int cpufreq_set_cur_state(struct thermal_cooling_device *cdev,
				 unsigned long state)
{
	int ret = -EINVAL;
	struct cpufreq_cooling_device *cpufreq_device;

	mutex_lock(&cooling_cpufreq_lock);
	list_for_each_entry(cpufreq_device, &cooling_cpufreq_list, node) {
		if (cpufreq_device && cpufreq_device->cool_dev == cdev) {
			ret = 0;
			break;
		}
	}
	if (!ret)
		ret = cpufreq_apply_cooling(cpufreq_device, state);

	mutex_unlock(&cooling_cpufreq_lock);

	return ret;
}

/*Bind cpufreq callbacks to thermal cooling device ops*/
static struct thermal_cooling_device_ops const cpufreq_cooling_ops = {
	.get_max_state = cpufreq_get_max_state,
	.get_cur_state = cpufreq_get_cur_state,
	.set_cur_state = cpufreq_set_cur_state,
};

/*Notifier for cpufreq policy change*/
static struct notifier_block thermal_cpufreq_notifier_block = {
	.notifier_call = cpufreq_thermal_notifier,
};

/**
 * cpufreq_cooling_register - function to create cpufreq cooling device.
 * @tab_ptr: table ptr containing the maximum value of frequency to be clipped
 *	for each cooling state.
 * @tab_size: count of entries in the above table.
 *	happen.
 */
struct thermal_cooling_device *cpufreq_cooling_register(
	struct freq_clip_table *tab_ptr, unsigned int tab_size)
{
	struct thermal_cooling_device *cool_dev;
	struct cpufreq_cooling_device *cpufreq_dev = NULL;
	struct freq_clip_table *clip_tab;
	unsigned int cpufreq_dev_count = 0;
	char dev_name[THERMAL_NAME_LENGTH];
	int ret = 0, id = 0, i;

	if (tab_ptr == NULL || tab_size == 0)
		return ERR_PTR(-EINVAL);

	list_for_each_entry(cpufreq_dev, &cooling_cpufreq_list, node)
		cpufreq_dev_count++;

	cpufreq_dev = kzalloc(sizeof(struct cpufreq_cooling_device),
			GFP_KERNEL);
	if (!cpufreq_dev)
		return ERR_PTR(-ENOMEM);

	/*Verify that all the entries of freq_clip_table are present*/
	for (i = 0; i < tab_size; i++) {
		clip_tab = ((struct freq_clip_table *)&tab_ptr[i]);
		if (!clip_tab->freq_clip_max || !clip_tab->mask_val
					|| !clip_tab->temp_level) {
			kfree(cpufreq_dev);
			return ERR_PTR(-EINVAL);
		}
		/*
		 *Consolidate all the cpumask for all the individual entries
		 *of the trip table. This is useful in resetting all the
		 *clipped frequencies to the normal level for each cpufreq
		 *cooling device.
		 */
		cpumask_or(&cpufreq_dev->allowed_cpus,
			&cpufreq_dev->allowed_cpus, clip_tab->mask_val);
	}

	cpufreq_dev->tab_ptr = tab_ptr;
	cpufreq_dev->tab_size = tab_size;

	ret = get_idr(&cpufreq_idr, &cpufreq_dev->id);
	if (ret) {
		kfree(cpufreq_dev);
		return ERR_PTR(-EINVAL);
	}

	sprintf(dev_name, "thermal-cpufreq-%d", cpufreq_dev->id);

	cool_dev = thermal_cooling_device_register(dev_name, cpufreq_dev,
						&cpufreq_cooling_ops);
	if (!cool_dev) {
		release_idr(&cpufreq_idr, cpufreq_dev->id);
		kfree(cpufreq_dev);
		return ERR_PTR(-EINVAL);
	}
	cpufreq_dev->id = id;
	cpufreq_dev->cool_dev = cool_dev;
	mutex_lock(&cooling_cpufreq_lock);
	list_add_tail(&cpufreq_dev->node, &cooling_cpufreq_list);

	/*Register the notifier for first cpufreq cooling device*/
	if (cpufreq_dev_count == 0)
		cpufreq_register_notifier(&thermal_cpufreq_notifier_block,
						CPUFREQ_POLICY_NOTIFIER);

	mutex_unlock(&cooling_cpufreq_lock);
	return cool_dev;
}
EXPORT_SYMBOL(cpufreq_cooling_register);

/**
 * cpufreq_cooling_unregister - function to remove cpufreq cooling device.
 * @cdev: thermal cooling device pointer.
 */
void cpufreq_cooling_unregister(struct thermal_cooling_device *cdev)
{
	struct cpufreq_cooling_device *cpufreq_dev = NULL;
	unsigned int cpufreq_dev_count = 0;

	mutex_lock(&cooling_cpufreq_lock);
	list_for_each_entry(cpufreq_dev, &cooling_cpufreq_list, node) {
		if (cpufreq_dev && cpufreq_dev->cool_dev == cdev)
			break;
		cpufreq_dev_count++;
	}

	if (!cpufreq_dev || cpufreq_dev->cool_dev != cdev) {
		mutex_unlock(&cooling_cpufreq_lock);
		return;
	}

	list_del(&cpufreq_dev->node);

	/*Unregister the notifier for the last cpufreq cooling device*/
	if (cpufreq_dev_count == 1) {
		cpufreq_unregister_notifier(&thermal_cpufreq_notifier_block,
					CPUFREQ_POLICY_NOTIFIER);
	}
	mutex_unlock(&cooling_cpufreq_lock);
	thermal_cooling_device_unregister(cpufreq_dev->cool_dev);
	release_idr(&cpufreq_idr, cpufreq_dev->id);
	kfree(cpufreq_dev);
}
EXPORT_SYMBOL(cpufreq_cooling_unregister);
