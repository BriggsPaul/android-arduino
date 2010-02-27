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
 *
 * NOTE: CODE AT THE BOTTOM OF THIS FILE IS UNDER A DIFFERENT LICENSE.
 */

// I/O pin definitions
#define LED 2
#define BUTTON 3
#define LIGHTS 5
#define PHOTORESISTOR 0

// numeric constants used in calculations
#define ILLUMINATION_THRESHOLD 350
#define MINUTES 60
#define START_HOUR 8
#define END_HOUR 21
#define STATE_DUMP_INTERVAL 3000

// FSM state definitions
#define STATE_START 0
#define STATE_TIME_UNSET 1
#define STATE_NIGHTTIME 2
#define STATE_DAYTIME 3

// opcode definitions
#define COMMAND_DELIMITER 0xff
#define COMMAND_RESET 0x2a
#define COMMAND_TIME_INIT (COMMAND_RESET + 1)

// state variables
int state = STATE_START;
int illuminated_seconds = 0;
int light_level = 0;
int lights_hold = 0;
int is_lit = 0;
int high_water_lit = 0;
int high_water_unlit = 0;
int low_water_lit = 10000;
int low_water_unlit = 10000;
int dark_history = 0;
unsigned long current_millis = 0, prev_millis = 0, state_dump_time = 0;

struct {
  unsigned long raw;
  int init;
  unsigned int hours;
  unsigned int minutes;
  unsigned int seconds;
} wall_time;

void setup() {
  pinMode(LIGHTS, OUTPUT);
  pinMode(LED, OUTPUT);
  pinMode(BUTTON, INPUT);
  Serial.begin(57600);
}

// clears all state value and drops back to the start state
void reset() {
  illuminated_seconds = light_level = is_lit = lights_hold = dark_history = 0;
  state_dump_time = current_millis = prev_millis = 0;
  wall_time.raw = wall_time.hours = wall_time.minutes = wall_time.seconds = 0;
  wall_time.init = 0;
  high_water_lit = high_water_unlit = 0;
  low_water_lit = low_water_unlit = 10000;
  state = STATE_TIME_UNSET;
  digitalWrite(LIGHTS, LOW);
}

// examines the serial/TTL input, looking for command codes, and executes any it finds
void process_incoming() {
  unsigned char cmd_type, opcode = 0;
  unsigned long l = 0, start = 0;
  while (Serial.available() >= 2) { // keep going as long as it we might have messages
    cmd_type = (unsigned char)(Serial.read() & 0xff);
    opcode = (unsigned char)(Serial.read() & 0xff);
    if (cmd_type != COMMAND_DELIMITER) {
      /* if we got gibberish or data was dropped, the delimiter is not the first byte seen,
       * which will cause us to get into a flush loop. This is fine only b/c we don't expect
       * continuous data over the serial port, so it's fine to keep flushing it until the other
       * side pauses in sending. At that point we'll catch up and re-sync with the other side
       */
      Serial.flush();
      return;
    }

    // correctly synced w/ other side on a delimiter byte, now check opcode
    switch (opcode) {
      case COMMAND_RESET:
        state = STATE_START; // eventually will call reset() on next looper pass
        break;
      case COMMAND_TIME_INIT:
        start = millis();
        while ((millis() - start) < 10) {
          if (Serial.available() >= 4)
            break;
        }
        // data shouldn't be arriving slowly or in chunks, so give up after waiting briefly
        if (Serial.available() < 4) {
          Serial.flush(); // results in a flush loop until we catch up with other side
        } else {
          // we have everything we need, now just set the time
          l = (((unsigned long)Serial.read()) << 24);
          wall_time.raw = l;
          l = (((unsigned long)Serial.read()) << 16);
          wall_time.raw = wall_time.raw | l;
          wall_time.raw = wall_time.raw | ((Serial.read() << 8) & 0xff00);
          wall_time.raw= wall_time.raw | (Serial.read() & 0xff);
	  wall_time.init = 1;
	  current_millis = prev_millis = millis();
          if (state == STATE_TIME_UNSET)
            state = STATE_DAYTIME;
        }
        break;
      default:
        // unknown opcode == another flush/resync
        Serial.flush();
    }
  }
}

/* Dumps the full state of the system for the other side to peruse. Because we dump our state
 * periodically, we don't need to worry about responding to commands -- the other side can
 * just monitor for changes in state.
 */
void dump_state() {
  Serial.print("state=");
  switch(state) {
    case STATE_START:
      Serial.println("START");
      break;
    case STATE_TIME_UNSET:
      Serial.println("TIME_UNSET");
      break;
    case STATE_DAYTIME:
      Serial.println("DAYTIME");
      break;
    case STATE_NIGHTTIME:
      Serial.println("NIGHTTIME");
      break;
  }
  Serial.print("current_time=");
  Serial.print(wall_time.hours, DEC);
  Serial.print(" ");
  if (wall_time.minutes < 10)
    Serial.print("0");
  Serial.print(wall_time.minutes, DEC);
  Serial.print(" ");
  if (wall_time.seconds < 10)
    Serial.print("0");
  Serial.println(wall_time.seconds, DEC);
  Serial.print("light_level=");
  Serial.println(light_level);
  Serial.print("light_on=");
  Serial.println(is_lit);
  Serial.print("illuminated_seconds=");
  Serial.println(illuminated_seconds);
  Serial.print("highest_light_when_lit=");
  Serial.println(high_water_lit);
  Serial.print("lowest_light_when_lit=");
  Serial.println(low_water_lit);
  Serial.print("highest_light_when_unlit=");
  Serial.println(high_water_unlit);
  Serial.print("lowest_light_when_unlit=");
  Serial.println(low_water_unlit);
  Serial.print("dark_history=");
  Serial.println(dark_history);
  Serial.println("");
}

// This is where the real work happens -- but only during daytime hours.
void do_daytime() {
  static unsigned long prev_time = 0;

  // if we've crossed into nighttime, switch state and bail
  if (wall_time.hours < START_HOUR || wall_time.hours >= END_HOUR) {
    state = STATE_NIGHTTIME;
    return;
  }

  // this gates execution so that code below this block happens only once per second instead of once per looper pass
  if (wall_time.raw != prev_time)
    prev_time = cur_time;
  else
    return;
 
  // read the light level & update our accumulator, dark_history.  
  light_level = analogRead(PHOTORESISTOR);
  if (light_level >= ILLUMINATION_THRESHOLD) {
    illuminated_seconds++;
    dark_history -= 1;
  } else {
    dark_history += 1;
  }
  // if we "accumulate too much dark", we turn the light on
  if (dark_history < 0) dark_history = 0;
  if (dark_history > 30) {
      lights_hold = 30 * MINUTES;
      is_lit = 1;    
      digitalWrite(LIGHTS, HIGH);    
  }

  // update our stats  
  if (is_lit) {
    if (light_level > high_water_lit) {
      high_water_lit = light_level;
    } else if (light_level < low_water_lit) {
      low_water_lit = light_level;
    }
  } else {
    if (light_level > high_water_unlit) {
      high_water_unlit = light_level;
    } else if (light_level < low_water_unlit) {
      low_water_unlit = light_level;
    }
  } 

  // check the 30-minute countdown timer to see if it's time to turn lights off
  if (lights_hold == 1) {
    is_lit = dark_history = 0;
    digitalWrite(LIGHTS, LOW);
  }
  lights_hold -= 1;
  if (lights_hold < 0) lights_hold = 0;
  // once the lights are off, we start "accumulating darkness" again
}

// Handles behavior when it's nightime.
void do_nighttime() {
  // Basically we just keep the lights off and sit and wait until daylight.
  if (wall_time.hours >= START_HOUR && wall_time.hours < END_HOUR) {
    state = STATE_DAYTIME;
    return;
  }
 
  is_lit = 0;
  digitalWrite(LIGHTS, LOW);
  if (wall_time.hours == 0 && wall_time.minutes == 0 && wall_time.seconds == 0) illuminated_seconds = 0;
}

void loop() {
  current_time = millis();
  if (wall_time.init) {
    wall_time.raw = current_time / 1000;
    wall_time.seconds = wall_time.raw % 60;
    wall_time.minutes = (wall_time.raw / 60) % 60;
    wall_time.hours = (wall_time.raw / (60 * 60)) % 24;
  }
  switch(state) {
    case STATE_START:
      reset();
      break;
    case STATE_TIME_UNSET:
      // no-op: do nothing until we get an incoming command to set the time
      break;
    case STATE_DAYTIME:
      do_daytime();
      break;
    case STATE_NIGHTTIME:
      do_nighttime();
      break;
  }
  
  process_incoming();

  if ((current_millis - state_dump_time) > STATE_DUMP_INTERVAL) {
    dump_state();
    state_dump_time = current_millis;
  }
}
