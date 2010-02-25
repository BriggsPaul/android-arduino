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
#include <DateTime.h>

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
unsigned long state_dump_time = 0;
int illuminated_seconds = 0;
time_t cur_time = 0, prev_time = 0;
int light_level = 0;
int lights_hold = 0;
int is_lit = 0;
int high_water_lit = 0;
int high_water_unlit = 0;
int low_water_lit = 10000;
int low_water_unlit = 10000;
int dark_history = 0;

void setup() {
  pinMode(LIGHTS, OUTPUT);
  pinMode(LED, OUTPUT);
  pinMode(BUTTON, INPUT);
  Serial.begin(57600);
}

// clears all state value and drops back to the start state
void reset() {
  illuminated_seconds = light_level = is_lit = lights_hold = dark_history = 0;
  state_dump_time = cur_time = prev_time = 0;
  high_water_lit = high_water_unlit = 0;
  low_water_lit = low_water_unlit = 10000;
  state = STATE_TIME_UNSET;
  digitalWrite(LIGHTS, LOW);
}

// examines the serial/TTL input, looking for command codes, and executes any it finds
void process_incoming() {
  unsigned char cmd_type, opcode = 0;
  time_t init_time = 0;
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
          init_time = l;
          l = (((unsigned long)Serial.read()) << 16);
          init_time = init_time | l;
          init_time = init_time | ((Serial.read() << 8) & 0xff00);
          init_time = init_time | (Serial.read() & 0xff);
          DateTime.sync(init_time);
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
  DateTime.available();
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
  Serial.print(DateTime.Hour, DEC);
  Serial.print(" ");
  Serial.print(DateTime.Minute, DEC);
  Serial.print(" ");
  Serial.println(DateTime.Second, DEC);
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
  // if we've crossed into nighttime, switch state and bail
  if (DateTime.Hour < START_HOUR || DateTime.Hour >= END_HOUR) {
    state = STATE_NIGHTTIME;
    return;
  }

  // this gates execution so that code below this block happens only once per second instead of once per looper pass
  cur_time = DateTime.now();
  if (cur_time != prev_time)
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
  if (DateTime.Hour >= START_HOUR && DateTime.Hour < END_HOUR) {
    state = STATE_DAYTIME;
    return;
  }
 
  is_lit = 0;
  digitalWrite(LIGHTS, LOW);
  if (DateTime.Hour == 0 && DateTime.Minute == 0 && DateTime.Second == 0) illuminated_seconds = 0;
}

void loop() {
  unsigned long current_time = 0;
  
  DateTime.available();
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

  current_time = millis();
  if ((current_time - state_dump_time) > STATE_DUMP_INTERVAL) {
    dump_state();
    state_dump_time = current_time;
  }
}

/*
 * NOTICE: APACHE-LICENSED CODE ENDS HERE. CODE BELOW THIS POINT HAS A
 * DIFFERENT LICENSE, AS BELOW.
 * 
 * The code below actually grants no license at all, and its use is thus
 * questionable. I will be writing it out at the earliest opportunity.
 */

/*
  DateTime.cpp - Arduino Date and Time library
  Copyright (c) Michael Margolis.  All right reserved.

  This library is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 
*/

extern "C" {
  // AVR LibC Includes
}
//#include <string.h> // for memset
#include "DateTime.h"
#include <wiring.h>

//extern unsigned long _time;

#define LEAP_YEAR(_year) ((_year%4)==0)
static  byte monthDays[]={31,28,31,30,31,30,31,31,30,31,30,31};

// private methods

void DateTimeClass::setTime(time_t time)
{
    // set the system time to the given time value (as seconds since Jan 1 1970)
    this->sysTime = time;  
	this->prevMillis = millis();
}

extern "C" void __cxa_pure_virtual(void) {
    while(1);
    } 

//******************************************************************************
//* DateTime Public Methods
//******************************************************************************

DateTimeClass::DateTimeClass()
{
   this->status = dtStatusNotSet;
}

time_t DateTimeClass::now()
{
  while( millis() - prevMillis >= 1000){
    this->sysTime++;
    this->prevMillis += 1000;
  }
  return sysTime;
}

void DateTimeClass::sync(time_t time) 
{
   setTime(time); 
   //status.isSynced = true;   // this will be set back to false if the clock resets 
   //status.isSet = true; // if this is true and isSynced is false then clock was reset using EEPROM -- TODO
   this->status = dtStatusSync;
}

boolean DateTimeClass::available()
{  
// refresh time components if clock is set (even if not synced), just return false if not set
   if(this->status != dtStatusNotSet) { 
      this->now(); // refresh sysTime   
      this->localTime(&this->sysTime,&Second,&Minute,&Hour,&Day,&DayofWeek,&Month,&Year)  ;     
	  return true;
   }
   else
      return false;
}
void DateTimeClass::localTime(time_t *timep,byte *psec,byte *pmin,byte *phour,byte *pday,byte *pwday,byte *pmonth,byte *pyear) {
// convert the given time_t to time components
// this is a more compact version of the C library localtime function

  time_t long epoch=*timep;
  byte year;
  byte month, monthLength;
  unsigned long days;
  
  *psec=epoch%60;
  epoch/=60; // now it is minutes
  *pmin=epoch%60;
  epoch/=60; // now it is hours
  *phour=epoch%24;
  epoch/=24; // now it is days
  *pwday=(epoch+4)%7;
  
  year=70;  
  days=0;
  while((unsigned)(days += (LEAP_YEAR(year) ? 366 : 365)) <= epoch) {
    year++;
  }
  *pyear=year; // *pyear is returned as years from 1900
  
  days -= LEAP_YEAR(year) ? 366 : 365;
  epoch -= days; // now it is days in this year, starting at 0
  //*pdayofyear=epoch;  // days since jan 1 this year
  
  days=0;
  month=0;
  monthLength=0;
  for (month=0; month<12; month++) {
    if (month==1) { // february
      if (LEAP_YEAR(year)) {
        monthLength=29;
      } else {
        monthLength=28;
      }
    } else {
      monthLength = monthDays[month];
    }
    
    if (epoch>=monthLength) {
      epoch-=monthLength;
    } else {
        break;
    }
  }
  *pmonth=month;  // jan is month 0
  *pday=epoch+1;  // day of month
}


time_t DateTimeClass::makeTime(byte sec, byte min, byte hour, byte day, byte month, int year ){
// converts time components to time_t 
// note year argument is full four digit year (or digits since 2000), i.e.1975, (year 8 is 2008)
  
   int i;
   time_t seconds;

   if(year < 69) 
      year+= 2000;
    // seconds from 1970 till 1 jan 00:00:00 this year
    seconds= (year-1970)*(60*60*24L*365);

    // add extra days for leap years
    for (i=1970; i<year; i++) {
        if (LEAP_YEAR(i)) {
            seconds+= 60*60*24L;
        }
    }
    // add days for this year
    for (i=0; i<month; i++) {
      if (i==1 && LEAP_YEAR(year)) { 
        seconds+= 60*60*24L*29;
      } else {
        seconds+= 60*60*24L*monthDays[i];
      }
    }

    seconds+= (day-1)*3600*24L;
    seconds+= hour*3600L;
    seconds+= min*60L;
    seconds+= sec;
    return seconds; 
}

// make one instance for DateTime class the user 
DateTimeClass DateTime = DateTimeClass() ;
