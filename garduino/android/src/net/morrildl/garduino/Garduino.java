/*
 * Copyright 2010 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License
 */

package net.morrildl.garduino;

import java.util.Map;

import android.app.Activity;
import android.app.ProgressDialog;
import android.bluetooth.BluetoothAdapter;
import android.os.Bundle;
import android.os.Handler;
import android.os.Message;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.TextView;

public class Garduino extends Activity {
	private Handler handler;
	private CommThread thread;
	private ProgressDialog dialog;

	/** Called when the activity is first created. */
	@Override
	public void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		setContentView(R.layout.main);
		handler = new Handler() {
			@SuppressWarnings("unchecked")
			@Override
			public void handleMessage(Message msg) {
				super.handleMessage(msg);
				Map<String, String> params = (Map<String, String>)msg.obj;
				
				String state = params.get("state");
				Log.e("booga", state);
				int imageResource;
				if ("DAYTIME".equals(state)) {
					imageResource = R.drawable.sun;
				} else if ("NIGHTTIME".equals(state)) {
					imageResource = R.drawable.moon;					
				} else if ("TIME_UNSET".equals(state)) {
					imageResource = R.drawable.clock;					
				} else {
					imageResource = R.drawable.qm;
				}
				((ImageView)findViewById(R.id.state_image)).setImageResource(imageResource);

				String value = params.get("current_time");
				((TextView)findViewById(R.id.garduino_time)).setText(value);

				value = params.get("dark_history");
				((TextView)findViewById(R.id.darkness)).setText(value);

				value = params.get("light_on");
				if ("1".equals(value))
					((TextView)findViewById(R.id.light_status)).setText("On");
				else if ("0".equals(value))
					((TextView)findViewById(R.id.light_status)).setText("Off");
				else
					((TextView)findViewById(R.id.light_status)).setText("Unknown");

				value = params.get("light_level");
				((TextView)findViewById(R.id.light_intensity)).setText(value);
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
		dialog = ProgressDialog.show(this, "Connecting", "Searching for a Bluetooth serial port...");
		thread = new CommThread(BluetoothAdapter.getDefaultAdapter(), dialog, handler);
		thread.start();
	}
	
	@Override
	public void onPause() {
		super.onPause();
		if (dialog != null && dialog.isShowing())
			dialog.dismiss();
		if (thread != null)
			thread.cancel();
		thread = null;
	}
}
