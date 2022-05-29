import oscP5.*;
import netP5.*;
import supercollider.*;
import javax.sound.midi.*;
import controlP5.*;
import java.util.*;
import java.util.Map;

long firstTs; //keep track of the first timestamp

HashMap < String, Integer > highScores;
HashMap < String, Float > configs; //song configurations (speed)

boolean chosenSong, chosenMode, isAndroid, chosenInstrument;

String filename, savefile, playerName, confFile, instrumentStr;

float speed; //speed of the song

PImage bg; //background
PImage gbg; //game background
PImage pointerImg;

OscP5 oscP5; //osc receiver
Synth synth; //current synth
Synth last; //keep track of the synth so that we can free it

ControlP5 cp5;

int screen; // 0 -> title screen, 1 -> in-game, 2 -> game over

class SongNote {
  int note;
  long ts; //timestamp
}

int m; // max number of notes
int numNotes; // number of notes of the song

SongNote[] song;

String [] instrumentList;

int n; // number of notes per octave
int currentBall;

class Ball {
  long pos; // x position
  boolean correct; // whether the score has already been incremented
  boolean penalized; // whether the score has already been decremented
}

Ball[] balls;

int line_x, radius, pointer_radius, score, combo;

float pointer_y, y;

void setup() {
  size(700, 700);
  textAlign(CENTER, CENTER);
  
  pointerImg = loadImage(dataPath("res/pointer.png"));
  
  instrumentList = new String[5];
  
  instrumentList[0] = "piano";
  instrumentList[1] = "guitar";
  instrumentList[2] = "bell";
  instrumentList[3] = "flute";
  instrumentList[4] = "tri";

  configs = new HashMap < String, Float > ();

  // we'll have a look in the data folder
  java.io.File folder = new java.io.File(dataPath("songs/"));

  // list the files in the data folder
  String[] filenames = folder.list();

  // load config file
  confFile = "config.dat";

  java.io.File fileConfFile = new java.io.File(dataPath(confFile));

  if (fileConfFile.exists()) {
    println("Loaded configs");
  } else {
    // create default configs
    println("Written default configs (must be edited by user)", fileConfFile.length());
    String[] temp = new String[filenames.length];

    for (int i = 0; i < filenames.length; ++i)
      temp[i] = filenames[i] + ";" + "1";

    saveStrings(dataPath(confFile), temp);
  }

  // ACTUAL LOAD configs
  String[] lines = loadStrings(dataPath(confFile));

  for (int j = 0; j < lines.length; j++) {
    String[] temp = split(lines[j], ';');
    configs.put(temp[0], Float.parseFloat(temp[1]));
  }

  // load high scores file
  savefile = "save.dat";

  java.io.File file = new java.io.File(dataPath(savefile));

  if (file.exists()) {
    println("Loaded high scores");
  } else {
    String[] temp = {};
    saveStrings(dataPath(savefile), temp);
  }

  bg = loadImage(dataPath("res/background.jpg"));
  gbg = loadImage(dataPath("res/gameBackground.jpg"));

  // init variables and stuff, don't waste time there

  m = 512;
  n = 12;

  currentBall = 0;

  chosenSong = chosenMode = chosenInstrument = false;

  highScores = new HashMap < String, Integer > ();

  List l = Arrays.asList(filenames);

  List modes = Arrays.asList("android", "ios");

  screen = 0; // start with title screen

  line_x = width - 100;
  score = 0;
  combo = 0;

  radius = 30;

  pointer_radius = 20;

  song = new SongNote[m];

  balls = new Ball[m];

  /* start oscP5, listening for incoming messages at port 12000 */
  oscP5 = new OscP5(this, 12000);

  cp5 = new ControlP5(this);

  int sizeX = 200;
  int sizeY = 200;
  
  int sizeX2 = 400;
  int sizeY2 = 200;

  cp5.addScrollableList("Songs")
    .setPosition(width / 3 - sizeX / 2, height / 2 - sizeY / 2 - 1 * height / 16)
    .setSize(sizeX, sizeY)
    .setBarHeight(40)
    .setItemHeight(40)
    .addItems(l)
    .setColorBackground(color(0, 0, 0));

  cp5.addScrollableList("Mode")
    .setPosition(width / 2 - sizeX2 / 2, height / 2 - sizeY2 / 2 + 9*height / 32)
    .setSize(sizeX2, sizeY2)
    .setBarHeight(40)
    .setItemHeight(40)
    .addItems(modes)
    .setColorBackground(color(0, 0, 0));
    
  cp5.addScrollableList("Instrument")
    .setPosition(2*width / 3 - sizeX / 2, height / 2 - sizeY / 2 - 1 * height / 16)
    .setSize(sizeX, sizeY)
    .setBarHeight(40)
    .setItemHeight(40)
    .addItems(instrumentList)
    .setColorBackground(color(0, 0, 0));

  sizeX = 80;
  sizeY = 40;

  cp5.addBang("Start")
    .setPosition(width / 2 - sizeX / 2, height - sizeY / 2 - height / 8)
    .setSize(sizeX, sizeY)
    .getCaptionLabel().align(ControlP5.CENTER, ControlP5.CENTER)
    .setColorBackground(color(0, 0, 0));
    
  instrumentStr = "tri";
  playSound(0, true); //preload sounds

  /*
  Why am I doing this?
  Because otherwise the game stutters when the first ball is hit
  By playing this unuseful sound, I make sure the game is ready
  to send osc messages
  As a lucky bonus, it seems like a title screen sound fx
  Bug -> feature
  */
}

void Mode(int n) {
  chosenMode = true;

  String modeStr = "" + cp5.get(ScrollableList.class, "Mode").getItem(n).get("name");

  isAndroid = modeStr.equals("android");
}

void Instrument(int n) {
  chosenInstrument = true;

  instrumentStr = "" + cp5.get(ScrollableList.class, "Instrument").getItem(n).get("name");
}

void Start() {
  // do this only if the song and the mode are selected
  if (chosenSong && chosenMode && chosenInstrument) {
    // PARSE MIDI
    try {
      String path = dataPath("songs/" + filename);
      File midiFile = new File(path);
      Sequence seq = MidiSystem.getSequence(midiFile);
      Track[] tracks = seq.getTracks();

      numNotes = 0;
      /* keep track of the last timestamp
      so that if there are more notes with the same ts
      the last are discarded and only the first
      is saved
      it's basically a simple polyphonic to monophonic adapter */
      long lastTs = 0;

      boolean first = true; // is it the first real note that I'm parsing?

      Track myTrack = tracks[1];

      for (int j = 0; j < myTrack.size() && numNotes < m; j++) {
        // get midi-message for every event
        if (myTrack.get(j).getMessage() instanceof ShortMessage) {
          ShortMessage m = (ShortMessage) myTrack.get(j).getMessage();

          // log note-on or note-off events
          int cmd = m.getCommand();
          int note = m.getData1();
          long ts = myTrack.get(j).getTick();

          if (cmd == ShortMessage.NOTE_ON && (ts != lastTs || first)) {
            song[numNotes] = new SongNote();
            song[numNotes].note = note;
            song[numNotes++].ts = ts;

            lastTs = ts;

            if (numNotes == 1) {
              firstTs = ts;
              first = false; // not the first anymore
            }
          }
        }
      }
    } catch (Exception e) {
      e.printStackTrace();
      exit();
    }

    balls = new Ball[numNotes];

    if (configs.containsKey(filename))
      speed = configs.get(filename);
    else
      speed = 1;

    println("first ts", firstTs);

    for (int i = 0; i < numNotes; i = i + 1) {
      balls[i] = new Ball();

      long ts = song[i].ts - firstTs; // normalize the timestamps so that the first one is zero

      balls[i].pos = -(long)(ts / speed); // scale the opposite of timestamp to convert it to position
      balls[i].correct = false;
      balls[i].penalized = false;
    }
    
    // go to in-game
    screen = 1;

    // remove drop-down menus and the button
    cp5.get(ScrollableList.class, "Songs").remove();
    cp5.get(ScrollableList.class, "Mode").remove();
    cp5.get(ScrollableList.class, "Instrument").remove();
    cp5.get(Bang.class, "Start").remove();
  }
}

void draw() {
  if (screen == 0) {
    background(bg);
    fill(255);
    textAlign(CENTER);
    fill(0);
    text("Welcome to chordophone champion, a rip off of guitar hero!", width / 2, height / 2 - 5 * height / 19);
    text("Select a song, an instrument and an input mode to play", width / 2, height / 2 + 20 - 5 * height / 19);
    fill(255);
  } else if (screen == 1) {
    background(gbg);
    fill(255);

    String[] note_names = {
      "C",
      "C#",
      "D",
      "D#",
      "E",
      "F",
      "F#",
      "G",
      "G#",
      "A",
      "A#",
      "B"
    };

    stroke(255);
    strokeWeight(6);
    // create horizontal lines
    for (int i = 0; i < n - 1; i = i + 1) {
      stroke(255);
      line(0, (i + 1) * width / (n), height, (i + 1) * width / (n));
    }

    // create note labels
    for (int i = 0; i < n; i = i + 1) {
      text(note_names[11 - i], width / (n), ((i + 1) * height / (n) - height / (2 * n + 6)));
    }

    strokeWeight(4);
    // create boundary between hitting and missing a ball
    fill(255);
    line(line_x, 0, line_x, width);
    
    fill(0);
    stroke(0);
    

    PFont font = createFont("arial bold", 15);

    // show score and combo
    fill(255);
    textFont(font);
    text("Score: " + score, width - 50, 20);
    text("Combo: " + combo, width - 50, 45);
    fill(0, 0, 0);

    pointer_y = y * 20 + 250;

    // pacman effect
    while (pointer_y < 0)
      pointer_y += height;

    pointer_y %= height;

    // draw the pointer
    fill(0, 0, 0);
    strokeWeight(5);
    stroke(255);
    image(pointerImg, line_x - 24, pointer_y - 24, 48, 48);

    for (int i = 0; i < numNotes; i = i + 1) {
      if(balls[i].pos >= 0 && balls[i].pos < width){
        // the note is modulo n
        long note = n - 1 - song[i].note % n;
        long pos = (2 * note + 1) * height / (2 * n);
        
        strokeWeight(2);
        
        drawGradient(balls[i].pos, pos, (int)note);
      }
    }

    fill(255);

    for (int i = currentBall; i < numNotes; i = i + 1) {
      // make balls move right
      balls[i].pos += 3;

      if (balls[i].pos > width) {
        currentBall = max(currentBall, i);

        if (currentBall + 1 == numNotes) {
          ++screen;

          if (last != null)
            last.free();

          String[] lines = loadStrings(dataPath(savefile));

          for (int j = 0; j < lines.length; j++) {
            String[] temp = split(lines[j], ';');
            lines[j] = temp[0] + " - " + temp[1] + " - " + temp[2];
            highScores.put(temp[0] + ";" + temp[1], Integer.parseInt(temp[2]));
          }

          int sizeX = 400;
          int sizeY = 200;

          cp5.addScrollableList("High scores: Player - Song - Score")
            .setPosition(width / 2 - sizeX / 2, height / 2 - 5 * height / 20)
            .setSize(sizeX, sizeY)
            .setBarHeight(40)
            .setItemHeight(40)
            .addItems(lines)
            .setColorBackground(color(0, 0, 0));

          sizeX = 200;
          sizeY = 40;

          PFont font2 = createFont("arial", 10);

          cp5.addTextfield("Username")
            .setPosition(width / 2 - sizeX / 2, height / 2 - sizeY / 2 + 4 * height / 16)
            .setSize(sizeX, sizeY)
            .setFont(font2)
            .setFocus(true)
            .setCaptionLabel("Insert your username")
            .setFont(font)
            .setColor(color(35, 161, 238))
            .setColorLabel(color(0, 0, 0))
            .setColorBackground(color(0, 0, 0));

          sizeX = 80;
          sizeY = 40;

          cp5.addBang("Submit")
            .setPosition(width / 2 - sizeX / 2, height - sizeY / 2 - height / 8)
            .setSize(sizeX, sizeY)
            .getCaptionLabel().align(ControlP5.CENTER, ControlP5.CENTER);
            
          cp5.addBang("Restart")
            .setPosition(width / 2 - sizeX / 2, height - sizeY / 2 - 3 * height / 8)
            .setSize(sizeX, sizeY)
            .getCaptionLabel().align(ControlP5.CENTER, ControlP5.CENTER);
        }

        if (!balls[i].correct & !balls[i].penalized) {
          if (score > 0) {
            score = score - 1;
          }
          combo = 0;
          balls[i].penalized = true;
        }
      }
    }
  } else if (screen == 2) {
    background(bg);
    fill(0);
    textAlign(CENTER);
    String str = "Score: " + score;
    text(str, width / 2, height / 2 + height / 8);
  }
}

void Songs(int n) {
  chosenSong = true;
  filename = "" + cp5.get(ScrollableList.class, "Songs").getItem(n).get("name");
}

/* incoming osc message are forwarded to the oscEvent method. */
void oscEvent(OscMessage theOscMessage) {
  if (!isAndroid) {
    if (theOscMessage.addrPattern().equals("/gyrosc/computer/gyro")) {
      y = -1 + 10 * theOscMessage.get(1).floatValue();
    }
  } else {
    if (theOscMessage.addrPattern().equals("/multisense/orientation/pitch")) {
      y = theOscMessage.get(0).floatValue();
    }
  }

  for (int i = currentBall; i < numNotes; i = i + 1) {
    long note = n - 1 - song[i].note % n;
    long pos = (2 * note + 1) * height / (2 * n);
    // hitbox computation
    if ((balls[i].pos > line_x - radius) && (balls[i].pos < line_x + radius) && !balls[i].correct) {
      if ((pointer_y > pos - radius) && (pointer_y < pos + radius)) {
        // score and combo management
        if (combo < 10)
          score += 1;
        else if (combo < 20)
          score += 2;
        else if (combo < 50)
          score += 3;
        else
          score += 5;
        combo++;
        balls[i].correct = true;
        playSound(song[i].note, false);
      }
    }
  }
}

void playSound(int n, boolean free) {
  // free the last synth
  if (last != null)
    last.free();
  // uses default sc server at 127.0.0.1:57110
  synth = new Synth(instrumentStr);

  // set initial arguments
  synth.set("amp", 0.5);
  synth.set("freq", 440 * pow(2, (float)(n - 69) / 12)); // convert midi to frequency
  
  // create synth
  synth.create();

  last = synth;
  
  if(free){
    delay(500);
    last.free();
  }
}

// implement a class that sorts a map by values
class ValueComparator implements Comparator < String > {
  Map < String, Integer > base;

  public ValueComparator(Map < String, Integer > base) {
    this.base = base;
  }

  // Note: this comparator imposes orderings that are inconsistent with equals
  public int compare(String a, String b) {
    if (base.get(a) >= base.get(b)) {
      return -1;
    } else {
      return 1;
    } // returning 0 would merge keys
  }
}

public void Submit() {
  playerName = cp5.get(Textfield.class, "Username").getText();

  if (playerName.isEmpty())
    return;

  cp5.get(Textfield.class, "Username").clear();

  highScores.put(playerName + ";" + filename, score);

  // sort highscore by descending score
  ValueComparator bvc = new ValueComparator(highScores);
  TreeMap < String, Integer > sorted_map = new TreeMap < String, Integer > (bvc);
  sorted_map.putAll(highScores);

  // we can't save the map directly to file, or at least not as readable text
  ArrayList < String > hsList = new ArrayList < String > ();

  for (Map.Entry < String, Integer > entry: sorted_map.entrySet()) {
    hsList.add(entry.getKey() + ";" + entry.getValue());
  }

  saveStrings(dataPath(savefile), hsList.toArray(new String[hsList.size()]));
  cp5.get(Textfield.class, "Username").remove();
  cp5.get(Bang.class, "Submit").remove();
}

void drawGradient(float x, float y, int note) {
   colorMode(HSB, 360, 100, 100);
   ellipseMode(RADIUS);
   noStroke();

   float h = (21 * (note+1)) % 255;
   for (int r = radius; r > 0; --r) {
     fill(h, 90, 90);
     ellipse(x, y, r, r);
     h = (h + 1) % 360;
   }

   colorMode(RGB,255,255,255);
 }

void Restart() {
  if(cp5.get(Textfield.class, "Username") != null){
    cp5.get(Textfield.class, "Username").remove();
    cp5.get(Bang.class, "Submit").remove();
  }
  cp5.get(ScrollableList.class, "High scores: Player - Song - Score").remove();
  cp5.get(Bang.class, "Restart").remove();
  setup();
}
