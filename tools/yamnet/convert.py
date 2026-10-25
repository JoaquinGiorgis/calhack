#!/usr/bin/env python3
"""Convert the bundled YAMNet waveform model without retraining or quantization.

Use coremltools9.0 / TensorFlow2.20.0 / NumPy2.4.6, as recorded in provenance.
The deployment app needs only CoreML; this converter runs on a development Mac.
"""
from pathlib import Path
import argparse
import time
import numpy as np
import tensorflow as tf
import coremltools as ct
from coremltools.converters.mil.frontend.tensorflow.tf_op_registry import register_tf_op
from coremltools.converters.mil.mil import Builder as mb

# coremltools has native complex_abs lowering but does not register TensorFlow's
# equivalent operation. This is a conversion-only bridge, not a runtime custom op.
@register_tf_op
def ComplexAbs(context, node):
    context.add(node.name, mb.complex_abs(x=context[node.inputs[0]], name=node.name))

@register_tf_op(override=True)
def RFFT(context, node):
    data = context[node.inputs[0]]
    n = int(context[node.inputs[1]].val[0])
    if n != 512 or not isinstance(data.shape[-1], (int, np.integer)):
        raise ValueError('This bounded converter expects the fixed YAMNet512-point RFFT')
    length = int(data.shape[-1])
    if length > n:
        raise ValueError('Unexpected YAMNet RFFT input length')
    if length < n:
        data = mb.pad(x=data, pad=np.array([0, n-length], dtype=np.int32))
    # Compute angles in Float64 BEFORE trig; CoreML's generic lowering creates
    # these phases in Float32, amplifying error in narrow-band input. Runtime
    # matrices remain Float32. This is exactly the nonnormalized one-sided DFT.
    phase = (2*np.pi/n) * np.outer(np.arange(n,dtype=np.float64), np.arange(n//2+1,dtype=np.float64))
    real = mb.matmul(x=data, y=np.cos(phase).astype(np.float32))
    imag = mb.matmul(x=data, y=(-np.sin(phase)).astype(np.float32))
    context.add(node.name, mb.complex(real_data=real, imag_data=imag, name=node.name))
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2] / 'pretrained/yamnet')
parser.add_argument('--output', type=Path, required=True, help='New .mlpackage directory')
args = parser.parse_args()
source = args.source.resolve()
output = args.output.resolve()
if output.suffix != '.mlpackage':
    parser.error('--output must end with .mlpackage')
if output.exists():
    parser.error('Output already exists; select a fresh path to preserve previous evidence')
output.parent.mkdir(parents=True, exist_ok=True)
model=tf.saved_model.load(str(source))
@tf.function(input_signature=[tf.TensorSpec(shape=[15600],dtype=tf.float32,name='waveform')])
def fixed(waveform):
    return tf.identity(model(waveform)[0][0],name='scores')
concrete=fixed.get_concrete_function()
print('TF',tf.__version__,'CT',ct.__version__,flush=True)
print('INPUTS',concrete.inputs[0],'OUTPUTS',concrete.outputs,flush=True)
start=time.perf_counter()
converted=ct.convert([concrete],source='tensorflow',convert_to='mlprogram',
                     inputs=[ct.TensorType(name='waveform',shape=(15600,),dtype=np.float32)],
                     minimum_deployment_target=ct.target.iOS16,compute_precision=ct.precision.FLOAT32,
                     compute_units=ct.ComputeUnit.CPU_ONLY)
spec=converted.get_spec()
print('SPEC INPUT',spec.description.input,'OUTPUT',spec.description.output,flush=True)
old=spec.description.output[0].name
if old!='scores':
    ct.utils.rename_feature(spec,old,'scores')
    converted=ct.models.MLModel(spec,weights_dir=converted.weights_dir,compute_units=ct.ComputeUnit.CPU_ONLY)
converted.short_description='YAMNet 521 AudioSet classes; 15600 Float32 mono samples at 16 kHz. Offline waveform frontend included.'
converted.author='TensorFlow Authors; converted for FortWatch'
converted.license='Apache License 2.0'
converted.input_description['waveform']='15600 mono Float32 samples at 16000 Hz, nominal range [-1,1]. No normalization beyond PCM scaling.'
converted.output_description['scores']='521 sigmoid scores in yamnet_class_map.csv order; not a calibrated probability distribution.'
converted.save(str(output))
print('SAVED', output, 'SECONDS',time.perf_counter()-start,flush=True)
print('PREDICT_ZERO',converted.predict({'waveform':np.zeros(15600,np.float32)})['scores'].shape,flush=True)
