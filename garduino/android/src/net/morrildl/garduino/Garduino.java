package net.morrildl.garduino;

import java.io.IOException;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.Map.Entry;

import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;
import android.os.Bundle;
import android.os.Handler;
import android.os.Message;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;

public class Garduino extends Activity {
	private Handler handler;
	private BluetoothDevice device;
	private CommThread thread;

	/** Called when the activity is first created. */
	@Override
	public void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		setContentView(R.layout.main);
		handler = new Handler() {
			@Override
			public void handleMessage(Message msg) {
				super.handleMessage(msg);
				Map<String, String> params = (Map<String, String>)msg.obj;
				StringBuffer sb = new StringBuffer();
				for (Entry<String, String> entry : params.entrySet()) {
					sb.append(entry.getKey()).append("=").append(entry.getValue()).append("\n");
				}
				((TextView)(findViewById(R.id.textarea))).setText(sb.toString());
			}			
		};
		
		((Button)findViewById(R.id.reset_button)).setOnClickListener(new View.OnClickListener() {
			public void onClick(View v) {
				byte[] bytes = new byte[] { (byte)0xff, 0x2a };
				thread.write(bytes);
			}
		});

		((Button)findViewById(R.id.set_time_button)).setOnClickListener(new View.OnClickListener() {
			public void onClick(View v) {
				byte[] bytes = new byte[6];
				bytes[0] = (byte)0xff;
				bytes[1] = 0x2b;
				long t = System.currentTimeMillis() / 1000 - 8*60*60;
				bytes[2] = (byte)((t & 0xff000000) >> 24);
				bytes[3] = (byte)((t & 0xff0000) >> 16);
				bytes[4] = (byte)((t & 0xff00) >> 8);
				bytes[5] = (byte)(t & 0xff);
				thread.write(bytes);
			}
		});
	}

	@Override
	public void onStart() {
		super.onStart();
		setupBluetooth();
	}
	
	@Override
	public void onPause() {
		super.onPause();
		if (thread != null)
			thread.cancel();
		thread = null;
	}

	private void setupBluetooth() {
		Log.e("setupBluetooth", "start");
		BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
		if (adapter == null)
			return;

		Set<BluetoothDevice> devices = adapter.getBondedDevices();
		device = null;
		for (BluetoothDevice curDevice : devices) {
			Log.e("setupBluetooth", curDevice.getName());
			if (curDevice.getName().matches(".*[Ff]ire[fF]ly.*")) {
				device = curDevice;
				break;
			}
		}
		if (device == null)
			device = adapter.getRemoteDevice("00:06:66:03:A7:52");

		Log.e("setupBluetooth", device.getName());
		BluetoothSocket socket = null;
		try {
			socket = device.createRfcommSocketToServiceRecord(UUID.fromString("00001101-0000-1000-8000-00805F9B34FB"));
			socket.connect();
		} catch (IOException e) {
			socket = null;
        	Log.e("setupBluetooth", "ioe", e);
		}
		if (socket == null) return;
		Log.e("setupBluetooth", "starting thread");

		thread = new CommThread(socket, handler);
		thread.start();
	}
}