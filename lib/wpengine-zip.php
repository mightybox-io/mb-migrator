<?php
// Map a WP Engine backup into the existing provider layout without extracting core or config.
try {
    if (!class_exists('ZipArchive')) {
        throw new RuntimeException('WP Engine ZIP support requires PHP with the zip extension');
    }
    $zip = new ZipArchive();
    if ($zip->open($argv[2], ZipArchive::RDONLY) !== true) {
        throw new RuntimeException('Cannot open backup ZIP');
    }
    $entries = [];
    $roots = [];
    for ($i = 0; $i < $zip->numFiles; $i++) {
        $name = $zip->getNameIndex($i);
        if (preg_match('/[\x00-\x1f\\\\]/', $name) || str_starts_with($name, '/') || preg_match('/^[A-Za-z]:/', $name)) {
            throw new RuntimeException('Unsafe ZIP entry');
        }
        $name = preg_replace('~^(?:\./)+~', '', $name);
        if (in_array('..', explode('/', $name), true) || in_array('.', explode('/', $name), true)) {
            throw new RuntimeException('Unsafe ZIP path');
        }
        $opsys = $attributes = 0;
        $zip->getExternalAttributesIndex($i, $opsys, $attributes);
        $type = ($attributes >> 16) & 0170000;
        if ($opsys === 3 && $type !== 0 && $type !== 0100000 && $type !== 0040000) {
            throw new RuntimeException('ZIP links and special files are not supported');
        }
        if (isset($entries[$name])) {
            throw new RuntimeException('Duplicate ZIP entry');
        }
        $entries[$name] = $i;
        if (preg_match('~^(.*)wp-content/mysql\.sql$~', $name, $m)) {
            $roots[] = $m[1];
        }
    }
    if (count($roots) !== 1) {
        throw new RuntimeException('Expected exactly one WP Engine wp-content/mysql.sql backup');
    }
    $root = $roots[0];
    $mapped = [];
    foreach ($entries as $name => $i) {
        if (!str_starts_with($name, $root)) continue;
        $relative = substr($name, strlen($root));
        if ($relative === 'wp-content/mysql.sql') {
            $dest = 'database-wpengine/site.sql';
        } elseif (preg_match('~^wp-content/(plugins|themes|uploads|mu-plugins)(/|$)~', $relative)) {
            $dest = 'htdocs/' . $relative;
        } elseif (!str_contains(rtrim($relative, '/'), '/') && !preg_match('~^(?:wp-.*\.php|index\.php|xmlrpc\.php|license\.txt|readme\.html|\.htaccess|\.user\.ini)$~i', $relative)) {
            $dest = 'htdocs/' . $relative;
        } else {
            continue;
        }
        $mapped[$dest] = $i;
    }
    if ($argv[1] === 'index') {
        foreach (array_keys($mapped) as $dest) echo $dest, "\n";
    } elseif ($argv[1] === 'extract') {
        $stage = realpath($argv[3]);
        if ($stage === false) throw new RuntimeException('Missing staging directory');
        $selected = array_slice($argv, 4);
        foreach ($mapped as $dest => $i) {
            $wanted = false;
            foreach ($selected as $path) {
                $path = preg_replace('~^\./~', '', $path);
                if ($dest === $path || str_starts_with($dest, rtrim($path, '/') . '/')) $wanted = true;
            }
            if (!$wanted) continue;
            $parts = explode('/', rtrim($dest, '/'));
            $current = $stage;
            foreach ($parts as $part) {
                $current .= '/' . $part;
                if (is_link($current)) throw new RuntimeException('Staging symlink conflict');
            }
            $output = $stage . '/' . $dest;
            if (str_ends_with($dest, '/')) {
                if (!is_dir($output) && !mkdir($output, 0700, true)) throw new RuntimeException('Cannot create directory');
                continue;
            }
            if (!is_dir(dirname($output)) && !mkdir(dirname($output), 0700, true)) throw new RuntimeException('Cannot create parent');
            $in = $zip->getStream($zip->getNameIndex($i));
            $out = fopen($output, 'wb');
            if (!$in || !$out) throw new RuntimeException('ZIP extraction failed');
            $copied = stream_copy_to_stream($in, $out);
            fclose($in);
            fclose($out);
            $stat = $zip->statIndex($i);
            if ($copied !== $stat['size'] || hash_file('crc32b', $output) !== sprintf('%08x', $stat['crc'])) {
                throw new RuntimeException('ZIP entry integrity check failed');
            }
            chmod($output, 0600);
        }
    } else {
        throw new RuntimeException('Unknown ZIP operation');
    }
    $zip->close();
} catch (Throwable $e) {
    fwrite(STDERR, '[wpengine:error] ' . $e->getMessage() . "\n");
    exit(1);
}
