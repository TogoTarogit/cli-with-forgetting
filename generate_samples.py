import torch
import tqdm
from model import OneHotCVAE
import torch.nn.functional as F
import os
import argparse
from torchvision.utils import save_image


def parse_args():
    parser = argparse.ArgumentParser()
    
    parser.add_argument(
        "--ckpt_folder", type=str, required=True, help="Path to folder of VAE"
    )
    
    parser.add_argument(
        "--n_samples", type=int, default=1000, help='Number of samples to generate'
    )
    
    parser.add_argument(
        "--batch_size", type=int, default=1000, help='Batch size. Keep it so that n_samples is divisible by batch_size.'
    )
    
    parser.add_argument(
        "--label_to_generate", type=int, default=0, help='Which MNIST class to generate'
    )
    parser.add_argument("--start_from_scratch", default= False , help='Start generating images from scratch even if some images already exist')
    args = parser.parse_args()
    assert args.n_samples % args.batch_size == 0, "Ensure n_samples is a multiple of batch_size!"
    return args


if __name__ == "__main__":
    
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    args = parse_args()
    ckpt = torch.load(os.path.join(args.ckpt_folder, "ckpts/ckpt.pt"), map_location=device)
    config = ckpt['config']
    
    # build model
    vae = OneHotCVAE(x_dim=config.x_dim, h_dim1= config.h_dim1, h_dim2=config.h_dim2, z_dim=config.z_dim)
    vae = vae.to(device)
    
    vae.load_state_dict(ckpt['model'])
    vae.eval()
    
    sample_dir = os.path.join(args.ckpt_folder, f"{args.label_to_generate}_samples")
    os.makedirs(sample_dir, exist_ok=True)
    
    # 画像を1から生成するかどうかのフラグを確認
    start_from_scratch = args.start_from_scratch or len(os.listdir(sample_dir)) < args.n_samples

    if start_from_scratch:
        # 既存の画像をクリア
        for f in os.listdir(sample_dir):
            os.remove(os.path.join(sample_dir, f))
        existing_images_count = 0
    else:
        existing_images_count = len([name for name in os.listdir(sample_dir) if os.path.isfile(os.path.join(sample_dir, name))])

    with torch.no_grad():
        for _ in tqdm.tqdm(range((args.n_samples - existing_images_count) // args.batch_size)):
            z = torch.randn((args.batch_size, config.z_dim)).to(device)
            c = (torch.ones(args.batch_size, dtype=int) * args.label_to_generate).to(device)
            c = F.one_hot(c, 10)
            samples = vae.decoder(z, c).view(-1, 1, 28, 28)
            for x in samples:
                existing_images_count += 1
                save_image(x, os.path.join(sample_dir, f'{existing_images_count}.png'))
                if existing_images_count >= args.n_samples:
                    break