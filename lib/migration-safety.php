<?php
/**
 * Plugin Name: MB Migrator Safety
 * Description: Explicit migration hold. Inspect with mb-migrator safety status; release with safety disable.
 */
if (!defined('ABSPATH')) exit;
add_filter('pre_get_ready_cron_jobs', '__return_empty_array', PHP_INT_MAX);
add_filter('pre_wp_mail', '__return_false', PHP_INT_MAX);
add_filter('action_scheduler_allow_async_request_runner', '__return_false', PHP_INT_MAX);
add_filter('action_scheduler_queue_runner_concurrent_batches', '__return_zero', PHP_INT_MAX);
add_filter('woocommerce_subscriptions_is_duplicate_site', '__return_true', PHP_INT_MAX);
