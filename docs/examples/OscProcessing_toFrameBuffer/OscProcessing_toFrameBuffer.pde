// OSC communication to Frame Buffer
import oscP5.*;
import netP5.*;
OscP5 sending;
NetAddress toMax;
float time = 0.0;
float increment = 0.01;

void setup() {
  size(720, 480);
  smooth();
  // OSC to MAX
  sending = new OscP5(this, 7401);
  toMax = new NetAddress("127.0.0.1", 7401);
}

void draw() {
  background(0);
  float n = noise(time) * 127;
  OscMessage variableToMax = new OscMessage("/ssss_osc_input");
  variableToMax.add(n*2%127); /* add a var to the osc message */
  variableToMax.add(n/2); /* add a second var to the osc message */
  variableToMax.add(n-10);
  variableToMax.add(n-20);
  variableToMax.add(n-30);
  variableToMax.add(n-40);
  variableToMax.add(n-50);
  variableToMax.add(n-20);
  variableToMax.add(n-30);
  variableToMax.add(n-40);
  variableToMax.add(n-50);
  /*Send Message */
  sending.send(variableToMax, toMax);
  time += increment;
}

/* incoming osc message are forwarded to the oscEvent method. */
void oscEvent(OscMessage theOscMessage) {
}