#!/usr/bin/env python3
"""Compare every YAMNet score against the original TensorFlow SavedModel.

Public-fixture file parity is conversion evidence, not live recognition accuracy.
No microphone or device access. Audio paths come from a public-sample manifest.
"""
from pathlib import Path
import argparse,json,csv,time,platform,hashlib,math
import numpy as np
from scipy.io import wavfile
from scipy.signal import resample_poly
import tensorflow as tf
import coremltools as ct
repo = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, default=repo / 'pretrained/yamnet')
parser.add_argument('--model', type=Path, default=repo / 'ios/FortWatchListener/Models/YAMNet.mlpackage')
parser.add_argument('--manifest', type=Path, required=True)
parser.add_argument('--output-directory', type=Path, required=True)
args = parser.parse_args()
root = args.output_directory.resolve()
root.mkdir(parents=True, exist_ok=True)
manifest = json.loads(args.manifest.read_text())
labels=[r['display_name'] for r in csv.DictReader((args.source/'assets/yamnet_class_map.csv').open())]
assert len(labels)==521
start=time.perf_counter(); original=tf.saved_model.load(str(args.source)); tf_load=time.perf_counter()-start
start=time.perf_counter(); converted=ct.models.MLModel(str(args.model),compute_units=ct.ComputeUnit.CPU_ONLY); ml_load=time.perf_counter()-start
all_ref=[];all_ml=[];tf_times=[];ml_times=[];rows=[];fixtures=[]
def evaluate_waveform(x):
    x=np.asarray(x,dtype=np.float32)
    assert x.shape==(15600,) and np.isfinite(x).all()
    start=time.perf_counter();ref=original(tf.constant(x))[0][0].numpy();tf_times.append(time.perf_counter()-start)
    start=time.perf_counter();out=np.asarray(converted.predict({'waveform':x})['scores'],np.float32);ml_times.append(time.perf_counter()-start)
    assert out.shape==(521,) and np.isfinite(out).all() and np.min(out)>=0 and np.max(out)<=1
    all_ref.append(ref);all_ml.append(out)
    error=np.abs(ref-out)
    return ref,out,float(error.max()),float(error.mean())
def top(scores,n=5):
    return [{'index':int(i),'label':labels[int(i)],'score':float(scores[i])} for i in np.argsort(-scores)[:n]]
for clip in manifest['clips']:
    sr,x=wavfile.read(clip['path'])
    assert x.ndim==1
    if np.issubdtype(x.dtype,np.integer):
        x=x.astype(np.float32)/float(max(abs(np.iinfo(x.dtype).min),np.iinfo(x.dtype).max+1))
    else: x=x.astype(np.float32)
    divisor=math.gcd(int(sr),16000)
    x=resample_poly(x,16000//divisor,int(sr)//divisor).astype(np.float32)
    windows=[];refs=[];outs=[]
    for offset in range(0,len(x)-15600+1,7680):
        ref,out,maxerr,meanerr=evaluate_waveform(x[offset:offset+15600]);refs.append(ref);outs.append(out)
        windows.append({'start_sample_16k':offset,'duration_samples':15600,'max_abs_error':maxerr,'mean_abs_error':meanerr,'tf_top5':top(ref),'coreml_top5':top(out),'tf_scores':ref.tolist(),'coreml_scores':out.tolist()})
        if offset==0 and clip['category'] in ['cat','rain','door_wood_knock'] and len(fixtures)<3:
            fixtures.append({'filename':clip['filename'],'start_sample_16k':offset,'waveform':x[offset:offset+15600].tolist(),'tensorflow_scores':ref.tolist()})
    ref_mean=np.mean(refs,axis=0);out_mean=np.mean(outs,axis=0)
    row={'filename':clip['filename'],'dataset_category':clip['category'],'source_rate':int(sr),'windows':windows,'tf_mean_top10':top(ref_mean,10),'coreml_mean_top10':top(out_mean,10),'max_abs_error':max(w['max_abs_error'] for w in windows)}
    rows.append(row)
    print(clip['category'],clip['filename'],'max_error',row['max_abs_error'],'top',top(out_mean,3),flush=True)
synthetics=[]
reference_cases=[]
for name,x in [('silence',np.zeros(15600,np.float32)),('tone_440Hz',(0.1*np.sin(2*np.pi*440*np.arange(15600)/16000)).astype(np.float32)),('triangle_64',((np.abs(np.arange(15600)%64-32)-16)/128).astype(np.float32)),('seeded_white_noise',np.random.default_rng(42).normal(0,.05,15600).astype(np.float32))]:
    ref,out,maxerr,meanerr=evaluate_waveform(x)
    synthetics.append({'name':name,'max_abs_error':maxerr,'mean_abs_error':meanerr,'tf_top5':top(ref),'coreml_top5':top(out)})
    if name!='seeded_white_noise':
        reference_cases.append({'name':name,'referenceScores':ref.tolist()})
a=np.stack(all_ref);b=np.stack(all_ml)
summary={'samples':len(all_ref),'public_clips':len(rows),'public_windows':sum(len(r['windows']) for r in rows),'synthetic_windows':len(synthetics),'maximum_absolute_error':float(np.max(np.abs(a-b))),'mean_absolute_error':float(np.mean(np.abs(a-b))),'top1_agreement_count':int(np.sum(np.argmax(a,axis=1)==np.argmax(b,axis=1))),'all_finite':bool(np.isfinite(b).all()),'pass_max_abs_error_1e_3':bool(np.max(np.abs(a-b))<1e-3)}
def timing(vals):return {'first_call_ms':vals[0]*1000,'warm_median_ms':float(np.median(vals[1:]))*1000,'warm_p95_ms':float(np.percentile(vals[1:],95))*1000,'warm_max_ms':max(vals[1:])*1000}
report={'host':platform.platform(),'tensorflow':tf.__version__,'coremltools':ct.__version__,'numpy':np.__version__,'compute_units':'CPU_ONLY','precision':'FLOAT32','input':{'name':'waveform','shape':[15600],'dtype':'float32','sample_rate':16000,'mono':True,'stride':7680},'output':{'name':'scores','shape':[521],'dtype':'float32','labels':labels},'preprocessing':'Public mono WAV PCM scale; scipy.signal.resample_poly to16k. Internal unchanged YAMNet Hann/STFT/mel/log frontend included in model. No amplitude normalization.','summary':summary,'timings':{'tensorflow_load_s':tf_load,'coreml_load_s':ml_load,'tensorflow_prediction':timing(tf_times),'coreml_prediction':timing(ml_times),'excludes':'File read and resampling; host only, not iPhone latency.'},'dataset_manifest':str(args.manifest.resolve()),'model_path':str(args.model.resolve()),'dataset_commit':manifest['commit'],'clips':rows,'synthetics':synthetics,'limits':['Numeric parity is conversion validation, not recognition accuracy.','Public file tests do not validate phone mic/FOA/room acoustics.','All521outputs preserved; overlapping and hierarchical scores are not mutually exclusive probabilities.','No threshold tuning or production policy changes.']}
(root/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
(root/'swift-parity-fixtures.json').write_text(json.dumps(fixtures)+'\n')
(root/'yamnet-reference-fixtures.json').write_text(json.dumps({'version':1,'source':'Original bundled TensorFlow YAMNet, without CoreML conversion','tensorflowVersion':tf.__version__,'sampleRate':16000,'sampleCount':15600,'outputCount':521,'classMapSHA256':hashlib.sha256((args.source/'assets/yamnet_class_map.csv').read_bytes()).hexdigest(),'maximumAbsoluteTolerance':0.001,'definitions':{'silence':'Float32(0) for all i','tone_440Hz':'Float32(0.1 * sin(2 * Double.pi * 440 * Double(i) / 16000))','triangle_64':'Float(abs((i % 64) - 32) - 16) / 128; exact binary fractions; no RNG'},'cases':reference_cases},indent=2)+'\n')
np.savez_compressed(root/'raw-parity-scores.npz',tensorflow=a,coreml=b)
print('SUMMARY',json.dumps(summary),flush=True)
print('TIMINGS',json.dumps(report['timings']),flush=True)
if not summary['pass_max_abs_error_1e_3']:raise SystemExit('Parity tolerance failed')
