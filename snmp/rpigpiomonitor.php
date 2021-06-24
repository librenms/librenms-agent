#!/usr/bin/env php
<?php
/**
 * rpigpiomonitor.php
 *
 * LibreNMS Raspberry Pi GPIO Monitor SNMP extension
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * @link      https://librenms.org
 * @copyright 2021 Denny Friebe
 * @author    Denny Friebe <denny.friebe@icera-network.de>
 */

function parseConfigFile($file, $process_sections = false, $scanner_mode = INI_SCANNER_NORMAL) {
    $explode_str = '.';
    $escape_char = "'";

    // load ini file the normal way
    $data = parse_ini_file($file, $process_sections, $scanner_mode);

    if (!$process_sections) {
        $data = array($data);
    }

    foreach ($data as $section_key => $section) {
        // loop inside the section
        foreach ($section as $key => $value) {
            if (strpos($key, $explode_str)) {
                if (substr($key, 0, 1) !== $escape_char) {
                    // key has a dot. Explode on it, then parse each subkeys
                    // and set value at the right place thanks to references
                    $sub_keys = explode($explode_str, $key);
                    $subs =& $data[$section_key];
                    foreach ($sub_keys as $sub_key) {
                        if (!isset($subs[$sub_key])) {
                            $subs[$sub_key] = [];
                        }
                        $subs =& $subs[$sub_key];
                    }
                    // set the value at the right place
                    $subs = $value;
                    // unset the dotted key, we don't need it anymore
                    unset($data[$section_key][$key]);
                }
                // we have escaped the key, so we keep dots as they are
                else {
                    $new_key = trim($key, $escape_char);
                    $data[$section_key][$new_key] = $value;
                    unset($data[$section_key][$key]);
                }
            }
        }
    }
    if (!$process_sections) {
        $data = $data[0];
    }
    return $data;
}

function validate_sensor_type($type) {
    switch ($type) {
        case "airflow":
        case "ber":
        case "charge":
        case "chromatic_dispersion":
        case "cooling":
        case "count":
        case "current":
        case "dbm":
        case "delay":
        case "eer":
        case "fanspeed":
        case "frequency":
        case "humidity":
        case "load":
        case "loss":
        case "power":
        case "power_consumed":
        case "power_factor":
        case "pressure":
        case "quality_factor":
        case "runtime":
        case "signal":
        case "snr":
        case "state":
        case "temperature":
        case "tv_signal":
        case "voltage":
        case "waterflow":
        case "percent":
            return true;
        default:
            return false;
    }
}

function validate_sensor_states($states) {
    if (is_array($states)) {
        foreach($states as $state_index => $state) {
            if (!isset($state["value"]) || !isset($state["generic"])) {
                continue;
            }

            if (!is_numeric($state["value"]) || !is_numeric($state["generic"])) {
                return false;
            }
        }
        return true;
    }
    return false;
}

function validate_sensor_limit($limit) {
    if (isset($limit) && is_numeric($limit)) {
        return true;
    }
    return false;
}

function get_rpi_serial() {
    if (file_exists("/proc/device-tree/serial-number")) {
        $rpi_serial = file_get_contents("/proc/device-tree/serial-number");
        //During the readout of serial-number additional characters are passed. (at this point I am not sure why)
        //To prevent these characters from being output and messing up the whole snmp string we only cut out the needed characters.
        $rpi_serial = substr($rpi_serial, 0, 16);
        return $rpi_serial;
    }
    return;
}

function get_sensor_current_value($sensor_data) {
    if (isset($sensor_data["io_gpio_pin"])) {
            $sensor_current_value = exec("gpio read " .$sensor_data["io_gpio_pin"]. " 2>&1", $tt, $retcode);
        } else {
            $sensor_current_value = exec($sensor_data["external_gpio_reader"]. " 2>&1", $tt, $retcode);
        }

    if (is_numeric($sensor_current_value)) {
        return $sensor_current_value;
    }

    return;
}

function validate_config($config, $rpi_serial) {
    if(!$rpi_serial) {
        echo "The serial number of your raspberry pi could not be read. Please check if you are using a DT enabled kernel and the file /proc/device-tree/serial-number is present. \n";
        echo "The serial number is required for creating a state sensor so that no sensor with the same name from another RPI overwrites it. \n";
    }

    foreach($config as $sensor_name => $sensor_data) {
        $valid = false;
        $gpio_reader_valid = true;

        if (!isset($sensor_data["type"]) || validate_sensor_type($sensor_data["type"]) == false) {
            echo "No valid type is configured for sensor ".$sensor_name."! \n";
        }

        if (isset($sensor_data["states"]) && validate_sensor_states($sensor_data["states"]) == false) {
            echo "No valid states is configured for sensor ".$sensor_name."! \n";
        }

        if (!$sensor_data["description"]) {
            echo "No valid description is configured for sensor ".$sensor_name."! \n";
        }

        if (isset($sensor_data["lowlimit"]) && validate_sensor_limit($sensor_data["lowlimit"]) == false) {
            echo "No valid lowlimit is configured for sensor ".$sensor_name."! \n";
        }

        if (isset($sensor_data["lowwarnlimit"]) && validate_sensor_limit($sensor_data["lowwarnlimit"]) == false) {
            echo "No valid lowwarnlimit is configured for sensor ".$sensor_name."! \n";
        }

        if (isset($sensor_data["warnlimit"]) && validate_sensor_limit($sensor_data["warnlimit"]) == false) {
            echo "No valid warnlimit is configured for sensor ".$sensor_name."! \n";
        }

        if (isset($sensor_data["highlimit"]) && validate_sensor_limit($sensor_data["highlimit"]) == false) {
            echo "No valid highlimit is configured for sensor ".$sensor_name."! \n";
        }

        if (!isset($sensor_data["io_gpio_pin"]) && !isset($sensor_data["external_gpio_reader"])) {
            echo "No IO GPIO pin or external GPIO readout program is configured for sensor ".$sensor_name."! \n";
            $gpio_reader_valid = false;
        }

        if (isset($sensor_data["external_gpio_reader"]) && !file_exists($sensor_data["external_gpio_reader"])) {
            echo "The external GPIO program for sensor ".$sensor_name." could not be found! Please check if the specified path is correct and the file exists. \n";
            $gpio_reader_valid = false;
        }

        if ($gpio_reader_valid) {
            $sensor_current_value = get_sensor_current_value($sensor_data);
            if (isset($sensor_current_value)) {
                echo "Current sensor value for ".$sensor_name.": " . $sensor_current_value . "\n";
                $valid = true;
            } else {
                echo "The current sensor value for ".$sensor_name." does not seem to be numeric! \n";
                if (isset($sensor_data["io_gpio_pin"])) {
                    echo "Please check if wiringpi is installed on this device! \n";
                } else {
                    echo "Please check if the external GPIO program outputs pure numeric values and if the required access rights are available to execute this program. \n";
                }
            }
        }

        if ($valid) {
            echo "The sensor ".$sensor_name." are configured correctly. \n\n";
        } else {
            echo "Please check your configuration for sensor ".$sensor_name.". \n\n";
        }
    }
}

function read_sensors($config, $rpi_serial) {
    if ($rpi_serial) {
        foreach($config as $sensor_name => $sensor_data) {
            if ((!isset($sensor_data["type"]) || validate_sensor_type($sensor_data["type"]) == false)
                || (isset($sensor_data["states"]) && validate_sensor_states($sensor_data["states"]) == false)
                || !$sensor_data["description"]
                || (isset($sensor_data["lowlimit"]) && validate_sensor_limit($sensor_data["lowlimit"]) == false)
                || (isset($sensor_data["lowwarnlimit"]) && validate_sensor_limit($sensor_data["lowwarnlimit"]) == false)
                || (isset($sensor_data["warnlimit"]) && validate_sensor_limit($sensor_data["warnlimit"]) == false)
                || (isset($sensor_data["highlimit"]) && validate_sensor_limit($sensor_data["highlimit"]) == false)
                || (!isset($sensor_data["io_gpio_pin"]) && !isset($sensor_data["external_gpio_reader"]))
                || (isset($sensor_data["external_gpio_reader"]) && !file_exists($sensor_data["external_gpio_reader"]))) {
                    continue; //The configuration of this sensor is not correct. Skip this one.
            }

            $sensor_current_value = get_sensor_current_value($sensor_data);
            if (!isset($sensor_current_value)) {
                continue; //The value read from the sensor does not correspond to a numerical value. Skip this one.
            }

            //If limit is not configured, we initialize the respective key to prevent "Undefined index" notes.
            if (!isset($sensor_data["lowlimit"])) {
                $sensor_data["lowlimit"] = null;
            }

            if (!isset($sensor_data["lowwarnlimit"])) {
                $sensor_data["lowwarnlimit"] = null;
            }

            if (!isset($sensor_data["warnlimit"])) {
                $sensor_data["warnlimit"] = null;
            }

            if (!isset($sensor_data["highlimit"])) {
                $sensor_data["highlimit"] = null;
            }

            echo $sensor_name."_".$rpi_serial.",".$sensor_data["type"].",".$sensor_data["description"].",".$sensor_data["lowlimit"].",".$sensor_data["lowwarnlimit"].",".$sensor_data["warnlimit"].",".$sensor_data["highlimit"]. ";";

            if(isset($sensor_data["states"])) {
                foreach($sensor_data["states"] as $state_descr => $state) {
                    echo $state["value"].",".$state["generic"].",".$state_descr.";";
                }
            }

            echo "\n" . $sensor_current_value . "\n";
        }
    }
}

$config = parseConfigFile('rpigpiomonitor.ini', true);
$rpi_serial = get_rpi_serial();

for ($i=0; $i < $argc; $i++) {
    if ($argv[$i] == "-validate") {
        validate_config($config, $rpi_serial);
        return;
    }
}

read_sensors($config, $rpi_serial);
?>

