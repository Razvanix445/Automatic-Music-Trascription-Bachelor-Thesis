import numpy as np
import matplotlib.pyplot as plt
import librosa
import librosa.display
import soundfile as sf
import os
import tempfile
import glob


def check_spectrogram_quality(spec_file_path, plot=True):
    """
    Perform quality checks on a mel spectrogram to ensure it's properly processed.

    Parameters:
    -----------
    spec_file_path : str
        Path to the spectrogram .npy file
    plot : bool
        To create the plots or not

    Returns:
    --------
    dict : Dictionary of test results with pass/fail indicators
    """
    results = {
        'file': os.path.basename(spec_file_path),
        'tests': {}
    }

    try:
        spec = np.load(spec_file_path)
        results['shape'] = spec.shape
    except Exception as e:
        results['error'] = f"Failed to load file: {str(e)}"
        return results

    # 1. Check if the spectrogram has the expected size
    n_mels, n_frames = spec.shape
    results['tests']['shape_check'] = {
        'pass': 200 <= n_mels <= 300 and n_frames > 100,
        'message': f"Shape: {spec.shape} - expecting ~229 mel bins and many time frames"
    }

    # 2. Check if the dB values in the .npy are within expected ranges
    min_val = np.min(spec)
    max_val = np.max(spec)
    results['tests']['db_range_check'] = {
        'pass': -100 <= min_val <= -60 and -20 <= max_val <= 10,
        'message': f"dB range: {min_val:.1f} to {max_val:.1f} dB - typical range is -80 to 0 dB"
    }

    # 3. Check no invalid values
    invalid_count = np.sum(~np.isfinite(spec))
    results['tests']['invalid_values_check'] = {
        'pass': invalid_count == 0,
        'message': f"Invalid values: {invalid_count} NaN/Inf values detected"
    }

    # 4. Check good distribution (not many zero values)
    spec_flat = spec.flatten()
    zeros_pct = np.sum(spec_flat == 0) / len(spec_flat) * 100
    results['tests']['zeros_check'] = {
        'pass': zeros_pct < 5,
        'message': f"Zeros percentage: {zeros_pct:.2f}% - should be low (<5%)"
    }

    # 5. Check energy concentration in frequency bands
    band_energies = np.mean(spec, axis=1)
    low_band_energy = np.mean(band_energies[:n_mels // 3])
    mid_band_energy = np.mean(band_energies[n_mels // 3:2 * n_mels // 3])
    high_band_energy = np.mean(band_energies[2 * n_mels // 3:])

    results['tests']['spectral_balance_check'] = {
        'pass': low_band_energy > high_band_energy,
        'message': f"Spectral balance: Low band: {low_band_energy:.1f}dB, Mid: {mid_band_energy:.1f}dB, High: {high_band_energy:.1f}dB"
    }

    # 6. Check dynamic range (difference between the loudest and quietest parts)
    percentile_range = np.percentile(spec, 99) - np.percentile(spec, 1)
    results['tests']['dynamic_range_check'] = {
        'pass': percentile_range > 30,
        'message': f"Dynamic range (99th-1st percentile): {percentile_range:.1f}dB - should be >30dB for music"
    }

    # 7. Check temporal variation (standard deviation across time)
    temporal_std = np.mean(np.std(spec, axis=1))
    results['tests']['temporal_variation_check'] = {
        'pass': temporal_std > 5,
        'message': f"Temporal variation: {temporal_std:.1f}dB standard deviation - should be >5dB"
    }

    results['pass_count'] = sum(1 for test in results['tests'].values() if test['pass'])
    results['total_tests'] = len(results['tests'])
    results['overall_pass'] = results['pass_count'] == results['total_tests']

    if plot:
        fig, axs = plt.subplots(3, 1, figsize=(12, 15))

        img = librosa.display.specshow(spec, x_axis='time', y_axis='mel', sr=16000,
                                       hop_length=512, fmax=8000, ax=axs[0])
        axs[0].set_title(f'Mel Spectrogram: {os.path.basename(spec_file_path)}')
        fig.colorbar(img, ax=axs[0], format='%+2.0f dB')

        axs[1].plot(band_energies)
        axs[1].set_title('Average Energy by Frequency Band')
        axs[1].set_xlabel('Mel Bin')
        axs[1].set_ylabel('Energy (dB)')
        axs[1].axvspan(0, n_mels // 3, alpha=0.2, color='green', label='Low Band')
        axs[1].axvspan(n_mels // 3, 2 * n_mels // 3, alpha=0.2, color='blue', label='Mid Band')
        axs[1].axvspan(2 * n_mels // 3, n_mels, alpha=0.2, color='red', label='High Band')
        axs[1].legend()

        axs[2].hist(spec_flat, bins=100, alpha=0.7)
        axs[2].set_title('Histogram of dB Values')
        axs[2].set_xlabel('dB Value')
        axs[2].set_ylabel('Count')
        axs[2].axvline(min_val, color='r', linestyle='--', label=f'Min: {min_val:.1f}dB')
        axs[2].axvline(max_val, color='g', linestyle='--', label=f'Max: {max_val:.1f}dB')
        axs[2].legend()

        plt.tight_layout()
        plt.show()

    print(f"Shape: {spec.shape}")
    print(f"Data type: {spec.dtype}")
    print(f"Min value: {np.min(spec):.2f} dB")
    print(f"Max value: {np.max(spec):.2f} dB")
    print(f"Mean value: {np.mean(spec):.2f} dB")

    print("\nSample values (top-left corner):")
    print(spec[:5, :5])

    print("\nValues for frequency bin 50 across time:")
    print(spec[50, :20])

    return results


def batch_check_spectrograms(output_dir, sample_size=10, plot=True):
    """
    Run quality checks on a batch of spectrograms from the output directory.

    Parameters:
    -----------
    output_dir : str
        Directory containing the processed spectrograms
    sample_size : int
        Number of random spectrograms to check
    plot : bool
        Whether to create plots for each checked spectrogram
    """
    spec_files = glob.glob(os.path.join(output_dir, "*_spec.npy"))

    if not spec_files:
        print(f"No spectrogram files found in {output_dir}")
        return

    if len(spec_files) > sample_size:
        import random
        spec_files = random.sample(spec_files, sample_size)

    print(f"Checking {len(spec_files)} spectrograms...")

    all_results = []
    for i, spec_file in enumerate(spec_files):
        print(f"Checking [{i + 1}/{len(spec_files)}] {os.path.basename(spec_file)}...")
        result = check_spectrogram_quality(spec_file, plot=plot)
        all_results.append(result)

        pass_count = result['pass_count']
        total_tests = result['total_tests']
        print(f"  Results: {pass_count}/{total_tests} tests passed")

        if not result['overall_pass']:
            print("  Failed tests:")
            for test_name, test_result in result['tests'].items():
                if not test_result['pass']:
                    print(f"    - {test_name}: {test_result['message']}")
        print()

    passing_specs = sum(1 for r in all_results if r['overall_pass'])
    print(f"\n===== OVERALL STATISTICS =====")
    print(f"Total spectrograms checked: {len(all_results)}")
    print(f"Passing spectrograms: {passing_specs} ({passing_specs / len(all_results) * 100:.1f}%)")
    print(f"Failing spectrograms: {len(all_results) - passing_specs}")

    if all_results:
        print("\nTest-by-test statistics:")
        for test_name in all_results[0]['tests'].keys():
            passing = sum(1 for r in all_results if r['tests'][test_name]['pass'])
            print(f"  {test_name}: {passing}/{len(all_results)} pass ({passing / len(all_results) * 100:.1f}%)")

    return all_results


if __name__ == '__main__':
    result = check_spectrogram_quality("dataset/spectrograms_mel/MIDI-Unprocessed_SMF_02_R1_2004_01-05_ORIG_MID--AUDIO_02_R1_2004_05_Track05_wav_segment_0_spec.npy", plot=True)

    # batch_check_spectrograms("dataset/spectrograms_mel", sample_size=10, plot=True)
