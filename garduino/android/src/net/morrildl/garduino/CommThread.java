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

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;

import android.bluetooth.BluetoothSocket;
import android.os.Handler;
import android.util.Log;

class CommThread extends Thread {
    private final BluetoothSocket socket;
    private final InputStream istream;
    private final OutputStream ostream;
    private final Handler handler;

    public CommThread(BluetoothSocket socket, Handler handler) {
        this.socket = socket;
        InputStream tmpIn = null;
        OutputStream tmpOut = null;
        this.handler = handler;

        try {
            tmpIn = socket.getInputStream();
            tmpOut = socket.getOutputStream();
        } catch (IOException e) { }

        istream = tmpIn;
        ostream = tmpOut;
    }

    public void run() {
    	StringBuffer sb = new StringBuffer();
        byte[] buffer = new byte[1024];  // buffer store for the stream
        int bytes; // bytes returned from read()
        String s;
        String message;
        int idx;
        HashMap<String, String> hm;
        String[] chunks;
        
        while (true) {
            try {
                // Read from the InputStream
                bytes = istream.read(buffer);
                sb.append(new String(buffer, 0, bytes));
                while ((idx = sb.indexOf("\r\n\r\n")) > -1) {
                    message = sb.substring(0, idx);
                	sb.replace(0, idx+4, "");
                	hm = new HashMap<String, String>();
                	for (String line : message.split("\n")) {
                		chunks = line.trim().split("=", 2);
                		if (chunks.length != 2) continue;
                		hm.put(chunks[0], chunks[1]);
                	}
                	handler.obtainMessage(0x2a, hm).sendToTarget();
                }
            } catch (IOException e) {
            	Log.e("reader", "ioe", e);
                break;
            }
        }
    }

    /* Call this from the main Activity to send data to the remote device */
    public void write(byte[] bytes) {
        try {
            ostream.write(bytes);
        } catch (IOException e) {
        	Log.e("writer", "ioe", e);
        }
    }

    /* Call this from the main Activity to shutdown the connection */
    public void cancel() {
        try {
            socket.close();
        } catch (IOException e) { }
    }
}
