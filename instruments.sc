(
(
SynthDef(\piano, {
	|
	out = 0, freq=440, gate=1, pan=0, amp=1, modIndex=0.2, mix=0.2, lfoSpeed=4.8, lfoDepth=0.1
	|

	var env1, env2, env3, env4;
	var osc1, osc2, osc3, osc4, snd;

	env1 = EnvGen.ar(Env.adsr(0.001, 1.25, 0.0, 0.04, curve:\lin),doneAction: Done.freeSelf);
	env2 = EnvGen.ar(Env.adsr(0.001, 1.00, 0.0, 0.04, curve:\lin),doneAction: Done.freeSelf);
	env3 = EnvGen.ar(Env.adsr(0.001, 1.50, 0.0, 0.04, curve:\lin),doneAction: Done.freeSelf);
	env4 = EnvGen.ar(Env.adsr(0.001, 1.50, 0.0, 0.04, curve:\lin),doneAction: Done.freeSelf);

	osc4 = SinOsc.ar(freq * 0.5) * 2pi * 1.071 * modIndex * env4;
	osc3 = SinOsc.ar(freq, osc4) * env3;

	osc2 = SinOsc.ar(freq * 15) *  2pi * 1.08 * env2;
	osc1 = SinOsc.ar(freq, osc2) * env1;

	snd = (osc3 * (1-mix)) + (osc1 * mix);

	snd = snd * (SinOsc.ar(lfoSpeed) * lfoDepth + 1);

	snd = snd * EnvGen.ar(Env.asr(0,1,0.1), gate, doneAction:2);
	snd = Pan2.ar(snd, pan, amp);

	Out.ar(out, snd);

}).store;
);

SynthDef(\bell, {|out= 0, pan= 0, freq = 440, amp= 0.1, dur= 2, t_trig= 1|
	var amps= #[1, 0.67, 1, 1.8, 2.67, 1.67, 1.46, 1.33, 1.33, 1, 1.33];
	var durs= #[1, 0.9, 0.65, 0.55, 0.325, 0.35, 0.25, 0.2, 0.15, 0.1, 0.075];
	var frqs= #[0.56, 0.56, 0.92, 0.92, 1.19, 1.7, 2, 2.74, 3, 3.76, 4.07];
	var dets= #[0, 1, 0, 1.7, 0, 0, 0, 0, 0, 0, 0];
	var src= Mix.fill(11, {|i|
		var env= EnvGen.ar(Env.perc(0.005, dur*durs[i], amps[i], -4.5), t_trig);
		SinOsc.ar(freq*frqs[i]+dets[i], 0, amp*env);
	});
	Out.ar(out, Pan2.ar(src, pan));
}).store;

(
SynthDef(\flute, {
	| freq=440, gate=1, amp=1 |
	var env = EnvGen.kr(Env.asr(0.1, 1, 0.1), gate, doneAction:2);
	var sig = VarSaw.ar(
		freq,
		width:LFNoise2.kr(1).range(0.2, 0.8)*SinOsc.kr(5, Rand(0.0, 1.0)).range(0.7,0.8))*0.25;
	sig = sig * env * amp;
	Out.ar(0, sig!2);
}).store;
);

(
SynthDef(\guitar, {
	var out = \out.kr(0);
	var pan = \pan.kr(0);
	var sustain = \sustain.kr(1);
	var freq = \freq.kr(440);
	var amp = \amp.kr(1) * (-12.dbamp);
	var snd, string;
	var env = EnvGen.ar(Env.linen(0.01, 0.98, 0.01, 1,-3), timeScale:sustain, doneAction:2);
	string = { |sfreq|
		var delay;
		delay = sfreq.reciprocal;
		Pluck.ar(
			SinOsc.ar(Line.ar(1000, 50, 0.01))
			*
			Env.perc(0.001, 0.1).ar,
			Impulse.ar(0.01), delay, delay, 5, 0.5)
	};
	snd = string.(freq) + string.(freq * 1.5) + string.(freq * 2);
	snd = (snd * 32.dbamp).tanh;
	snd = RLPF.ar(snd, 3000, 0.5);
	snd = (snd * 32.dbamp).tanh;
	snd = RLPF.ar(snd, 500, 0.5);
	snd = (snd * 32.dbamp).tanh;
	snd = LeakDC.ar(snd);
	snd = DelayC.ar(snd, 0.1, SinOsc.kr(2, [0, 1pi]).range(0, 1e-4));
	// uncomment for reverb 3.10
	// snd = snd + (NHHall.ar(snd, 1) * -5.dbamp);
	snd * -20.dbamp;
	Out.ar(out, Pan2.ar(snd, pan));
	//OffsetOut.ar(out, DirtPan.ar(snd, ~dirt.numChannels, pan, env));
}).store;
);

(
SynthDef(\tri, {
	|gate=1, amp=1, freq=440, panpos=0, envdur=1|
	var sig, pan;
	sig=LFTri.ar(freq,0,EnvGen.ar(Env.perc(0.001,envdur,amp,-15),gate,doneAction:2));
		pan=Pan2.ar(sig,panpos,1);
		Out.ar(0,pan)
}).add
);
)
