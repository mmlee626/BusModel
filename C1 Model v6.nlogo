extensions [palette]

breed [buses bus]
breed [students student]
breed [indicators indicator]

globals [
  ticks-per-minute  ; Conversion rate: 1 tick = 1 minute / 7.017
  travel-times                 ; Tracks last (200) student's travel times
  speed-limit
  speed-min
  east-num
  west-num
  max-num
  time-until-transition
  remaining-transition-time
  is-transition?               ; true when currently transition time
]

patches-own [
  is-campus?            ; true if the patch is a campus
  campus-name           ; name of the campus (East or West)
  num-of-bus-loading    ; true if bus is currently loading at that campus
]

buses-own [
  speed         ; patches per tick
  bus-type      ; type of bus: "single" or "double"
  cur-capacity  ; number of student currently on a C1
  max-capacity  ; maximum capacity depending on 1 or 2 connected buses
  wait-time     ; # of ticks waiting on each campus
  is-unloading? ; true if bus is currently unloading students
  is-loading?   ; true if bus is currently loading students
  unload-speed  ; per 100 ticks
  load-speed    ; per 100 ticks
]

students-own [
  bus-num       ; bus number or -1 if not on bus
  target-loc    ; the campus the student wants to get to
  lifetime      ; time alive
]

to setup
  clear-all
  set ticks-per-minute calculate-conversion
  set travel-times []
  set speed-limit bus-speed
  set speed-min 0
  set east-num 0
  set west-num 0
  set max-num 250
  set time-until-transition transition-spacing
  set remaining-transition-time 0
  set is-transition? False

  setup-road
  setup-buses number-of-buses
  setup-endpoints
  reset-ticks
end

to-report calculate-conversion
  report ((max-pxcor - 6) - (min-pxcor + 6)) / bus-speed / minutes-per-traversal
end

to setup-road
  ask patches [
    set pcolor green - random-float 0.5

    if pxcor >= min-pxcor + 6 and pxcor <= max-pxcor - 6 and pycor = 1 [ set pcolor grey - 2.5 + random-float 0.25 ]
    if pxcor >= min-pxcor + 6 and pxcor <= max-pxcor - 6 and pycor = -1 [ set pcolor grey - 2.5 + random-float 0.25 ]
    if pxcor >= min-pxcor + 3 and pxcor < min-pxcor + 6 and pycor >= -1 and pycor <= 1 [ set pcolor blue ]
    if pxcor > max-pxcor - 6 and pxcor <= max-pxcor - 3 and pycor >= -1 and pycor <= 1 [ set pcolor red ]
  ]
end

to setup-buses [bus-count]
  if number-of-buses > world-width [
    user-message (word
      "There are too many cars for the amount of road. "
      "Please decrease the NUMBER-OF-CARS slider to below "
      (world-width + 1) " and press the SETUP button again. "
      "The setup has stopped.")
    stop
  ]

  ; create the required number of buses
  create-buses bus-count [

    ; initialize a bus
    let is-double-bus (random 2) = 0  ; 50% chance for single/double bus
    ifelse is-double-bus = True [
      set bus-type "double"
      set max-capacity double-cap
      set color 63                    ; green
    ] [
      set bus-type "single"
      set max-capacity single-cap
      set color 126                   ; purple
    ]

    set label-color 46
    set speed speed-limit
    set wait-time bus-wait-time
    set is-loading? False
    set is-unloading? False

    let min-roadx min-pxcor + 6
    let max-roadx max-pxcor - 6

    ; spaces the buses out evenly
    ifelse bus-count mod 2 = 0 [
      let even-spacing (max-roadx - min-roadx) / (bus-count / 2 + 1)
      ifelse who < bus-count / 2 [
        setxy (min-roadx + even-spacing * (who + 1)) 1
        set heading 90
      ] [
        setxy (min-roadx + even-spacing * (bus-count - who)) -1
        set heading -90
      ]
    ] [
      ifelse who < (bus-count + 1) / 2 [
        let oddtop-spacing (max-roadx - min-roadx) / ((bus-count + 1) / 2 + 1)
        setxy (min-roadx + oddtop-spacing * (who + 1)) 1
        set heading 90
      ] [
        let oddbot-spacing (max-roadx - min-roadx) / ((bus-count + 1) / 2)
        setxy (min-roadx + oddbot-spacing * (bus-count - who)) -1
        set heading -90
      ]
    ]
  ]
end

; initializes the two campuses
to setup-endpoints
  ask patches with [ pcolor = red ] [
    set is-campus? true
    set campus-name "East"
    set num-of-bus-loading -1
  ]
  add-east-students random (max-num / 3)
  ask patches with [ pcolor = blue ] [
    set is-campus? true
    set campus-name "West"
    set num-of-bus-loading -1
  ]
  add-west-students random (max-num / 3)
  ask students [ ifelse show-people? [ show-turtle ] [ hide-turtle ] ]
end

to go
  tick

  ; global time procedures
  update-transition-timer
  ifelse is-transition? [ draw-indicator ] [ undraw-indicator ]

  ; student procedures
  generate-students
  ask students [ ifelse show-people? [ show-turtle ] [ hide-turtle ] set lifetime lifetime + 1 ]
  ask students with [ bus-num != -1] [ move-to-bus ]

  ; bus procedures
  ask buses [

    ; bus movement
    set speed-limit bus-speed
    let bus-ahead one-of buses-on patch-ahead 1
    ifelse bus-ahead != nobody
      [ slow-down-bus bus-ahead ]
      [ speed-up-bus ]
    if speed < speed-min [ set speed speed-min ]
    if speed > speed-limit [ set speed speed-limit ]

    ; bus loading/unloading
    if [ is-campus? = True ] of patch-ahead 1 [
      let id who
      ifelse ([ num-of-bus-loading = id ] of patch-ahead 1) or ([ num-of-bus-loading = -1 ] of patch-ahead 1) [
        wait-at-campus
      ] [
        set speed 0
        unload-students
      ]
    ]
    if [ is-campus? = True ] of patch-ahead 2 and speed = 0 [ unload-students ]
    if [ is-campus? = True ] of patch-ahead 3 and speed = 0 [ unload-students ]
    (ifelse is-unloading? = True [ unload-students ] is-loading? = True [ load-students ] [ forward speed ])

    set label cur-capacity
  ]

  ; calculate average travel time
  update-student-satisfaction

  tick
end

to update-transition-timer
  if time-until-transition = 0 and not is-transition? [
    set is-transition? True
    set remaining-transition-time transition-duration
  ]
  if time-until-transition > 0 [ set time-until-transition time-until-transition - 1 ]
  if remaining-transition-time > 0 [ set remaining-transition-time remaining-transition-time - 1 ]
  if remaining-transition-time = 0 and is-transition? [
    set is-transition? False
    set time-until-transition transition-spacing
  ]
end

to draw-indicator
  ask indicators [ die ]
  create-indicators 1 [
    set shape "circle"
    set size 3
    set color yellow
    setxy 0 3.5
  ]
end

to undraw-indicator
  ask indicators [ die ]
  create-indicators 1 [
    set shape "circle"
    set size 3
    set color grey
    setxy 0 3.5
  ]
end


; create students on each campus
to generate-students
  if east-num < max-num [
    let num-generated 1
    ifelse is-transition? [ set num-generated rate-to-num transition-arrival-rate ] [ set num-generated rate-to-num default-arrival-rate ]
    if num-generated + east-num > max-num [ set num-generated max-num - east-num ]
    add-east-students num-generated
  ]
  if west-num < max-num [
    let num-generated 1
    ifelse is-transition? [ set num-generated rate-to-num transition-arrival-rate ] [ set num-generated rate-to-num default-arrival-rate ]
    if num-generated + west-num > max-num [ set num-generated max-num - west-num ]
    add-west-students num-generated
  ]

  ; move students away from center of campus so we can see the bus easier
  if students-on patch (max-pxcor - 4) 0 != nobody [
    ask students-on patch (max-pxcor - 4) 0 [ setxy (max-pxcor - 4 + random-float 2 - 1) (random-float 2 - 1) ]
  ]
  if students-on patch (min-pxcor + 4) 0 != nobody [
    ask students-on patch (min-pxcor + 4) 0 [ setxy (min-pxcor + 4 + random-float 2 - 1) (random-float 2 - 1) ]
  ]
end

to add-east-students [n]
  set east-num east-num + n
  create-students n [
    setxy one-of (range (max-pxcor - 5) (max-pxcor - 3) 0.01) one-of (range -1 1 0.01)
    set shape "person"
    set size 0.7
    set bus-num -1
    set target-loc "West"
    set lifetime 0
  ]
end

to add-west-students [n]
  set west-num west-num + n
  create-students n [
    setxy one-of (range (min-pxcor + 3) (min-pxcor + 5) 0.01) one-of (range -1 1 0.01)
    set shape "person"
    set size 0.7
    set bus-num -1
    set target-loc "East"
    set lifetime 0
  ]
end

; if student is loaded onto bus then keep student attached to the bus
to move-to-bus
  palette:set-transparency 95
  move-to bus bus-num
end

; acceleration and deceleration procedures
to slow-down-bus [ bus-ahead ]
  set speed [ speed ] of bus-ahead - deceleration
end

to speed-up-bus
  set speed speed + acceleration
end

; loading/unloading bus logic
to wait-at-campus
  ifelse wait-time > 0 [
    ifelse heading = 90 [
      set ycor 0
      set xcor max-pxcor - 4
      let id who
      ask patches with [ campus-name = "East" ] [ set num-of-bus-loading id ]
    ]
    [
      set ycor 0
      set xcor min-pxcor + 4
      let id who
      ask patches with [ campus-name = "West" ] [ set num-of-bus-loading id ]
    ]

    if cur-capacity > 0 and is-loading? = False [ set is-unloading? True ]
    if cur-capacity = 0 and is-loading? = False [ set is-unloading? False set is-loading? True ]
    if cur-capacity >= max-capacity and is-loading? = True [ set wait-time 0 leave-campus ]

    set wait-time wait-time - 1
  ] [ leave-campus ]
end

; leaving campus bus procedure
to leave-campus
  ifelse heading = 90 [
    set heading 270
    set ycor -1 set xcor max-pxcor - 7
    ask patches with [ campus-name = "East" ] [ set num-of-bus-loading -1 ]
  ] [
    set heading 90
    set ycor 1
    set xcor min-pxcor + 6
    ask patches with [ campus-name = "West" ] [ set num-of-bus-loading -1 ]
  ]
  set wait-time bus-wait-time
  set is-unloading? False
  set is-loading? False
end

; unloading bus procedure
to unload-students
  set unload-speed bus-unload-speed
  if cur-capacity > 0 [
    let num-unloading rate-to-num unload-speed
    if num-unloading > cur-capacity [ set num-unloading cur-capacity ]
    let id who
    ask n-of num-unloading students with [ bus-num = id ] [ set travel-times lput lifetime travel-times die ]
    set cur-capacity cur-capacity - num-unloading
  ]
end

; loading bus procedure
to load-students
  set load-speed bus-load-speed
  let num-loading rate-to-num load-speed
  ifelse heading = 90
  [
    if east-num > 0 [
      if num-loading > east-num [ set num-loading east-num ]
      if num-loading + cur-capacity > max-capacity [ set num-loading max-capacity - cur-capacity ]
      set east-num east-num - num-loading
      set cur-capacity cur-capacity + num-loading
      let id who
      ask n-of num-loading students with [ target-loc = "West" and bus-num = -1 ] [ set bus-num id ]
    ]
  ]
  [
    if west-num > 0 [
      if num-loading > west-num [ set num-loading west-num ]
      if num-loading + cur-capacity > max-capacity [ set num-loading max-capacity - cur-capacity ]
      set west-num west-num - num-loading
      set cur-capacity cur-capacity + num-loading
      let id who
      ask n-of num-loading students with [ target-loc = "East" and bus-num = -1 ] [ set bus-num id ]
    ]
  ]
end



; calculate average student travel time
to update-student-satisfaction
  if length travel-times > smoothness [ set travel-times sublist travel-times (length travel-times - smoothness) (length travel-times) ]
end

; # per 100 ticks -> # per tick
to-report rate-to-num [rate]
  let definite floor (rate / 100)
  let chance-for-student rate mod 100
  let extra 0
  if chance-for-student != 0 and random (100 / chance-for-student) = 0 [ set extra 1 ]
  report (definite + extra)
end

; Copyright 1997 Uri Wilensky.
; Modified by Matthew Lee and Alice Zhang.
; ECON 113FS Final Project
@#$#@#$#@
GRAPHICS-WINDOW
60
225
983
399
-1
-1
15.0
1
10
1
1
1
0
0
0
1
-30
30
-5
5
1
1
1
minutes
30.0

BUTTON
39
83
111
118
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
119
83
190
118
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SLIDER
53
28
257
61
number-of-buses
number-of-buses
1
20
6.0
1
1
NIL
HORIZONTAL

SLIDER
1196
97
1331
130
deceleration
deceleration
0
.1
0.02
.001
1
NIL
HORIZONTAL

SLIDER
1196
57
1331
90
acceleration
acceleration
0
0.1
0.05
.001
1
NIL
HORIZONTAL

PLOT
609
18
984
213
Number of Students
time (ticks)
students
0.0
10.0
0.0
250.0
true
true
"" ""
PENS
"west" 1.0 0 -13345367 true "" "plot west-num"
"east" 1.0 0 -2674135 true "" "plot east-num"

MONITOR
830
340
937
385
Students on East
east-num
1
1
11

MONITOR
105
345
217
390
Students on West
west-num
17
1
11

MONITOR
430
345
602
390
Average Student Travel Time
(mean travel-times) / ticks-per-minute
1
1
11

SLIDER
1006
17
1183
50
default-arrival-rate
default-arrival-rate
10
500
40.0
10
1
NIL
HORIZONTAL

SLIDER
1006
97
1181
130
bus-load-speed
bus-load-speed
10
1000
370.0
10
1
NIL
HORIZONTAL

BUTTON
199
83
271
118
go-once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
1006
137
1181
170
bus-unload-speed
bus-unload-speed
10
1000
730.0
10
1
NIL
HORIZONTAL

SLIDER
1006
177
1181
210
bus-wait-time
bus-wait-time
5
100
70.0
5
1
NIL
HORIZONTAL

PLOT
320
17
595
212
Average Student Travel Time
time (ticks)
travel time
0.0
10.0
5.0
25.0
true
false
"" ""
PENS
"travel time" 1.0 0 -1264960 true "" "if length travel-times > 0\n[ plot (mean travel-times) / (ticks-per-minute) ]"

SLIDER
1005
315
1180
349
minutes-per-traversal
minutes-per-traversal
0.1
15
7.0
0.1
1
NIL
HORIZONTAL

SLIDER
1196
17
1331
50
bus-speed
bus-speed
0
2
0.5
0.1
1
NIL
HORIZONTAL

TEXTBOX
49
152
221
190
purple - single bus
14
126.0
1

TEXTBOX
49
173
208
213
green - double bus
14
63.0
1

SLIDER
1005
225
1180
259
transition-duration
transition-duration
10
500
270.0
10
1
NIL
HORIZONTAL

SLIDER
1005
265
1180
299
transition-spacing
transition-spacing
10
1200
1030.0
10
1
NIL
HORIZONTAL

MONITOR
560
235
670
280
Transition Time Left
remaining-transition-time / ticks-per-minute
2
1
11

MONITOR
365
235
480
280
Time Until Transition
time-until-transition / ticks-per-minute
2
1
11

SLIDER
1006
57
1181
90
transition-arrival-rate
transition-arrival-rate
10
500
220.0
10
1
NIL
HORIZONTAL

MONITOR
1005
355
1113
401
Ticks per Minute
ticks-per-minute
3
1
11

SWITCH
1192
316
1329
350
show-people?
show-people?
1
1
-1000

SLIDER
190
138
298
171
single-cap
single-cap
5
150
70.0
5
1
NIL
HORIZONTAL

SLIDER
190
178
298
211
double-cap
double-cap
5
150
100.0
5
1
NIL
HORIZONTAL

SLIDER
1158
362
1293
396
smoothness
smoothness
1
300
200.0
1
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

This model models the movement of cars on a highway. Each car follows a simple set of rules: it slows down (decelerates) if it sees a car close ahead, and speeds up (accelerates) if it doesn't see a car ahead. The model demonstrates how traffic jams can form even without any accidents, broken bridges, or overturned trucks.  No "centralized cause" is needed for a traffic jam to form.

## HOW TO USE IT

Click on the SETUP button to set up the cars.

Set the NUMBER-OF-CARS slider to change the number of cars on the road.

Click on GO to start the cars moving.  Note that they wrap around the world as they move, so the road is like a continuous loop.

The ACCELERATION slider controls the rate at which cars accelerate (speed up) when there are no cars ahead.

When a car sees another car right in front, it matches that car's speed and then slows down a bit more.  How much slower it goes than the car in front of it is controlled by the DECELERATION slider.

## THINGS TO NOTICE

Traffic jams can start from small "seeds."  These cars start with random positions and random speeds. If some cars are clustered together, they will move slowly, causing cars behind them to slow down, and a traffic jam forms.

Even though all of the cars are moving forward, the traffic jams tend to move backwards. This behavior is common in wave phenomena: the behavior of the group is often very different from the behavior of the individuals that make up the group.

The plot shows three values as the model runs:

* the fastest speed of any car (this doesn't exceed the speed limit!)

* the slowest speed of any car

* the speed of a single car (turtle 0), painted red so it can be watched.

Notice not only the maximum and minimum, but also the variability -- the "jerkiness" of one vehicle.

Notice that the default settings have cars decelerating much faster than they accelerate. This is typical of traffic flow models.

Even though both ACCELERATION and DECELERATION are very small, the cars can achieve high speeds as these values are added or subtracted at each tick.

## THINGS TO TRY

In this model there are three sliders that can affect the tendency to create traffic jams: the initial NUMBER-OF-CARS, ACCELERATION, and DECELERATION.

Look for patterns in how these settings affect the traffic flow.  Which variable has the greatest effect?  Do the patterns make sense?  Do they seem to be consistent with your driving experiences?

Set DECELERATION to zero.  What happens to the flow?  Gradually increase DECELERATION while the model runs.  At what point does the flow "break down"?

## EXTENDING THE MODEL

Try other rules for speeding up and slowing down.  Is the rule presented here realistic? Are there other rules that are more accurate or represent better driving strategies?

In reality, different vehicles may follow different rules. Try giving different rules or ACCELERATION/DECELERATION values to some of the cars.  Can one bad driver mess things up?

The asymmetry between acceleration and deceleration is a simplified representation of different driving habits and response times. Can you explicitly encode these into the model?

What could you change to minimize the chances of traffic jams forming?

What could you change to make traffic jams move forward rather than backward?

Make a model of two-lane traffic.

## NETLOGO FEATURES

The plot shows both global values and the value for a single car, which helps one watch overall patterns and individual behavior at the same time.

The `watch` command is used to make it easier to focus on the red car.

The `speed-limit` and `speed-min` variables are set to constant values. Since they are the same for every car, these variables could have been defined as globals rather than turtle variables. We have specified them as turtle variables since modifications or extensions to this model might well have every car with its own speed-limit values.

## RELATED MODELS

- "Traffic Basic Utility": a version of "Traffic Basic" including a utility function for the cars.

- "Traffic Basic Adaptive": a version of "Traffic Basic" where cars adapt their acceleration to try and maintain a smooth flow of traffic.

- "Traffic Basic Adaptive Individuals": a version of "Traffic Basic Adaptive" where each car adapts individually, instead of all cars adapting in unison.

- "Traffic 2 Lanes": a more sophisticated two-lane version of the "Traffic Basic" model.

- "Traffic Intersection": a model of cars traveling through a single intersection.

- "Traffic Grid": a model of traffic moving in a city grid, with stoplights at the intersections.

- "Traffic Grid Goal": a version of "Traffic Grid" where the cars have goals, namely to drive to and from work.

- "Gridlock HubNet": a version of "Traffic Grid" where students control traffic lights in real-time.

- "Gridlock Alternate HubNet": a version of "Gridlock HubNet" where students can enter NetLogo code to plot custom metrics.

## HOW TO CITE

If you mention this model or the NetLogo software in a publication, we ask that you include the citations below.

For the model itself:

* Wilensky, U. (1997).  NetLogo Traffic Basic model.  http://ccl.northwestern.edu/netlogo/models/TrafficBasic.  Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

Please cite the NetLogo software as:

* Wilensky, U. (1999). NetLogo. http://ccl.northwestern.edu/netlogo/. Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

## COPYRIGHT AND LICENSE

Copyright 1997 Uri Wilensky.

![CC BY-NC-SA 3.0](http://ccl.northwestern.edu/images/creativecommons/byncsa.png)

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 License.  To view a copy of this license, visit https://creativecommons.org/licenses/by-nc-sa/3.0/ or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

Commercial licenses are also available. To inquire about commercial licenses, please contact Uri Wilensky at uri@northwestern.edu.

This model was created as part of the project: CONNECTED MATHEMATICS: MAKING SENSE OF COMPLEX PHENOMENA THROUGH BUILDING OBJECT-BASED PARALLEL MODELS (OBPML).  The project gratefully acknowledges the support of the National Science Foundation (Applications of Advanced Technologies Program) -- grant numbers RED #9552950 and REC #9632612.

This model was developed at the MIT Media Lab using CM StarLogo.  See Resnick, M. (1994) "Turtles, Termites and Traffic Jams: Explorations in Massively Parallel Microworlds."  Cambridge, MA: MIT Press.  Adapted to StarLogoT, 1997, as part of the Connected Mathematics Project.

This model was converted to NetLogo as part of the projects: PARTICIPATORY SIMULATIONS: NETWORK-BASED DESIGN FOR SYSTEMS LEARNING IN CLASSROOMS and/or INTEGRATED SIMULATION AND MODELING ENVIRONMENT. The project gratefully acknowledges the support of the National Science Foundation (REPP & ROLE programs) -- grant numbers REC #9814682 and REC-0126227. Converted from StarLogoT to NetLogo, 2001.

<!-- 1997 2001 MIT -->
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

bus
false
0
Polygon -7500403 true true 15 206 15 150 15 120 30 105 270 105 285 120 285 135 285 206 270 210 30 210
Rectangle -16777216 true false 36 126 231 159
Line -7500403 false 60 135 60 165
Line -7500403 false 60 120 60 165
Line -7500403 false 90 120 90 165
Line -7500403 false 120 120 120 165
Line -7500403 false 150 120 150 165
Line -7500403 false 180 120 180 165
Line -7500403 false 210 120 210 165
Line -7500403 false 240 135 240 165
Rectangle -16777216 true false 15 174 285 182
Circle -16777216 true false 48 187 42
Rectangle -16777216 true false 240 127 276 205
Circle -16777216 true false 195 187 42
Line -7500403 false 257 120 257 207

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
setup
repeat 180 [ go ]
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
1
@#$#@#$#@
