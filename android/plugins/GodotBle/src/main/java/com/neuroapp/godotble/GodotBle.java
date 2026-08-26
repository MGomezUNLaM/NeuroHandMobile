package com.neuroapp.godotble;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanResult;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

public class GodotBle extends GodotPlugin {
    private static final String TAG = "GodotBle";
    
    // UUIDs para HM-10 (UART)
    private static final UUID SERVICE_UUID = UUID.fromString("0000ffe0-0000-1000-8000-00805f9b34fb");
    private static final UUID CHAR_UUID = UUID.fromString("0000ffe1-0000-1000-8000-00805f9b34fb");
    private static final UUID CLIENT_CHARACTERISTIC_CONFIG = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");

    private BluetoothAdapter bluetoothAdapter;
    private BluetoothLeScanner bluetoothLeScanner;
    private BluetoothGatt bluetoothGatt;
    
    private boolean isScanning = false;
    private Handler handler = new Handler(Looper.getMainLooper());
    
    // Guardar StringBuilder para ir acumulando los bytes de Arduino hasta encontrar '\n'
    private StringBuilder incomingDataBuffer = new StringBuilder();

    public GodotBle(Godot godot) {
        super(godot);
        BluetoothManager bluetoothManager = (BluetoothManager) getActivity().getSystemService(Context.BLUETOOTH_SERVICE);
        if (bluetoothManager != null) {
            bluetoothAdapter = bluetoothManager.getAdapter();
        }
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "GodotBle";
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("ble_device_found", String.class, String.class));
        signals.add(new SignalInfo("ble_connected", String.class));
        signals.add(new SignalInfo("ble_disconnected"));
        signals.add(new SignalInfo("ble_flex_updated", Integer.class));
        signals.add(new SignalInfo("ble_fsr_updated", Integer.class));
        signals.add(new SignalInfo("ble_data_received", String.class));
        signals.add(new SignalInfo("ble_error", String.class));
        signals.add(new SignalInfo("ble_scan_started"));
        signals.add(new SignalInfo("ble_scan_stopped"));
        return signals;
    }

    @UsedByGodot
    public void requestPermissions() {
        Activity activity = getActivity();
        if (activity == null) return;

        java.util.List<String> permissions = new java.util.ArrayList<>();

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(activity, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.BLUETOOTH_SCAN);
            }
            if (ContextCompat.checkSelfPermission(activity, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.BLUETOOTH_CONNECT);
            }
            if (ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.ACCESS_FINE_LOCATION);
            }
        } else {
            if (ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.ACCESS_FINE_LOCATION);
            }
            if (ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.ACCESS_COARSE_LOCATION);
            }
        }

        if (!permissions.isEmpty()) {
            ActivityCompat.requestPermissions(activity, permissions.toArray(new String[0]), 101);
        }
    }

    @UsedByGodot
    public void startScan() {
        Activity activity = getActivity();
        if (activity == null) return;

        if (bluetoothAdapter == null) {
            BluetoothManager bluetoothManager = (BluetoothManager) activity.getSystemService(Context.BLUETOOTH_SERVICE);
            if (bluetoothManager != null) {
                bluetoothAdapter = bluetoothManager.getAdapter();
            }
        }

        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled()) {
            emitSignal("ble_error", "Por favor activa el Bluetooth");
            return;
        }

        // Comprobación y solicitud automática de permisos si faltan
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(activity, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions();
                emitSignal("ble_error", "Permiso Bluetooth requerido");
                return;
            }
        } else {
            if (ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions();
                emitSignal("ble_error", "Permiso de Ubicación requerido");
                return;
            }
        }

        if (isScanning) return;

        bluetoothLeScanner = bluetoothAdapter.getBluetoothLeScanner();
        if (bluetoothLeScanner == null) {
            emitSignal("ble_error", "Scanner Bluetooth no disponible");
            return;
        }

        isScanning = true;
        bluetoothLeScanner.startScan(scanCallback);
        emitSignal("ble_scan_started");
        
        // Detener escaneo automáticamente después de 10 segundos
        handler.postDelayed(() -> stopScan(), 10000);
    }

    @UsedByGodot
    public void stopScan() {
        if (!isScanning || bluetoothLeScanner == null) return;
        
        try {
            // El chequeo de permisos para stopScan es obligatorio en SDK S+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (ContextCompat.checkSelfPermission(getActivity(), Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED) {
                    bluetoothLeScanner.stopScan(scanCallback);
                }
            } else {
                bluetoothLeScanner.stopScan(scanCallback);
            }
        } catch (Exception e) {
            Log.e(TAG, "Error deteniendo scan", e);
        }
        
        isScanning = false;
        emitSignal("ble_scan_stopped");
    }

    @UsedByGodot
    public void connectDevice(String address) {
        if (bluetoothAdapter == null) return;
        
        try {
            BluetoothDevice device = bluetoothAdapter.getRemoteDevice(address);
            if (device == null) {
                emitSignal("ble_error", "Dispositivo no encontrado");
                return;
            }
            
            stopScan();
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (ContextCompat.checkSelfPermission(getActivity(), Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                    emitSignal("ble_error", "Permiso CONNECT denegado");
                    return;
                }
            }
            
            bluetoothGatt = device.connectGatt(getActivity(), false, gattCallback);
        } catch (Exception e) {
            emitSignal("ble_error", "Error al conectar: " + e.getMessage());
        }
    }

    @UsedByGodot
    public void disconnectDevice() {
        if (bluetoothGatt != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (ContextCompat.checkSelfPermission(getActivity(), Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED) {
                    bluetoothGatt.disconnect();
                }
            } else {
                bluetoothGatt.disconnect();
            }
        }
    }

    private ScanCallback scanCallback = new ScanCallback() {
        @Override
        public void onScanResult(int callbackType, ScanResult result) {
            super.onScanResult(callbackType, result);
            BluetoothDevice device = result.getDevice();
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (ContextCompat.checkSelfPermission(getActivity(), Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                    return;
                }
            }
            
            String name = null;
            if (result.getScanRecord() != null) {
                name = result.getScanRecord().getDeviceName();
            }
            if (name == null || name.isEmpty()) {
                name = device.getName();
            }
            if (name == null || name.isEmpty()) {
                name = "Unknown";
            }
            String address = device.getAddress();
            
            emitSignal("ble_device_found", name, address);
        }
        
        @Override
        public void onScanFailed(int errorCode) {
            super.onScanFailed(errorCode);
            emitSignal("ble_error", "Fallo escaneo: " + errorCode);
        }
    };

    private BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        @Override
        public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (ContextCompat.checkSelfPermission(getActivity(), Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) return;
                }
                gatt.discoverServices();
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                emitSignal("ble_disconnected");
                if (bluetoothGatt != null) {
                    bluetoothGatt.close();
                    bluetoothGatt = null;
                }
            }
        }

        @Override
        public void onServicesDiscovered(BluetoothGatt gatt, int status) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                BluetoothGattCharacteristic characteristic = gatt.getService(SERVICE_UUID).getCharacteristic(CHAR_UUID);
                if (characteristic != null) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        if (ContextCompat.checkSelfPermission(getActivity(), Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) return;
                    }
                    gatt.setCharacteristicNotification(characteristic, true);
                    
                    BluetoothGattDescriptor descriptor = characteristic.getDescriptor(CLIENT_CHARACTERISTIC_CONFIG);
                    if (descriptor != null) {
                        descriptor.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
                        gatt.writeDescriptor(descriptor);
                    }
                    
                    // Emitir conexion
                    String name = gatt.getDevice().getName();
                    if (name == null) name = "HM-10";
                    emitSignal("ble_connected", name);
                }
            }
        }

        @Override
        public void onCharacteristicChanged(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic) {
            if (CHAR_UUID.equals(characteristic.getUuid())) {
                byte[] data = characteristic.getValue();
                if (data != null && data.length > 0) {
                    String text = new String(data);
                    incomingDataBuffer.append(text);
                    
                    // Leer lineas enteras
                    int newlineIdx;
                    while ((newlineIdx = incomingDataBuffer.indexOf("\n")) != -1) {
                        String line = incomingDataBuffer.substring(0, newlineIdx).trim();
                        incomingDataBuffer.delete(0, newlineIdx + 1);
                        
                        if (!line.isEmpty()) {
                            emitSignal("ble_data_received", line);
                        }
                        
                        if (line.startsWith("FLEX:")) {
                            try {
                                String valStr = line.substring(5).trim();
                                int flexValue = Integer.parseInt(valStr);
                                emitSignal("ble_flex_updated", flexValue);
                            } catch (NumberFormatException e) {
                                // Ignorar si llega basura
                            }
                        } else if (line.startsWith("FSR:")) {
                            try {
                                String valStr = line.substring(4).trim();
                                int fsrValue = Integer.parseInt(valStr);
                                emitSignal("ble_fsr_updated", fsrValue);
                            } catch (NumberFormatException e) {
                                // Ignorar si llega basura
                            }
                        }
                    }
                }
            }
        }
    };
}
