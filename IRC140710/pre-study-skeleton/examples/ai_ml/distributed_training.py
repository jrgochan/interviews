#!/usr/bin/env python3
"""
Distributed PyTorch Training Example for HPC Environments

This example demonstrates:
1. Multi-node distributed training using PyTorch DDP
2. Integration with Slurm for resource allocation
3. Proper initialization for HPC cluster environments
4. Performance monitoring and logging

Usage:
  srun python distributed_training.py --epochs 10 --batch-size 64
"""

import os
import argparse
import time
import socket
from datetime import timedelta

import torch
import torch.nn as nn
import torch.optim as optim
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP
from torch.utils.data import DataLoader, DistributedSampler
from torch.utils.tensorboard import SummaryWriter

import torchvision
import torchvision.transforms as transforms

def setup_distributed():
    """Initialize distributed training environment"""
    
    # Get rank and world size from environment variables set by Slurm/mpirun
    if 'SLURM_PROCID' in os.environ:
        rank = int(os.environ['SLURM_PROCID'])
        world_size = int(os.environ['SLURM_NTASKS'])
        local_rank = int(os.environ['SLURM_LOCALID'])
        
        # Get master address from Slurm
        if 'SLURM_STEP_NODELIST' in os.environ:
            # Parse nodelist to get first node as master
            import subprocess
            result = subprocess.run(['scontrol', 'show', 'hostname', 
                                   os.environ['SLURM_STEP_NODELIST']], 
                                  capture_output=True, text=True)
            master_addr = result.stdout.split('\n')[0]
        else:
            master_addr = socket.gethostname()
            
        master_port = os.environ.get('MASTER_PORT', '12355')
        
    elif 'OMPI_COMM_WORLD_RANK' in os.environ:
        # OpenMPI environment
        rank = int(os.environ['OMPI_COMM_WORLD_RANK'])
        world_size = int(os.environ['OMPI_COMM_WORLD_SIZE'])
        local_rank = int(os.environ['OMPI_COMM_WORLD_LOCAL_RANK'])
        master_addr = os.environ.get('MASTER_ADDR', 'localhost')
        master_port = os.environ.get('MASTER_PORT', '12355')
        
    else:
        # Single node training
        rank = 0
        world_size = 1
        local_rank = 0
        master_addr = 'localhost'
        master_port = '12355'
    
    print(f"Rank {rank}: Initializing distributed training")
    print(f"  World size: {world_size}")
    print(f"  Local rank: {local_rank}")
    print(f"  Master: {master_addr}:{master_port}")
    
    # Set local rank for GPU assignment
    if torch.cuda.is_available():
        torch.cuda.set_device(local_rank)
        backend = 'nccl'
        print(f"  Using NCCL backend with GPU {local_rank}")
    else:
        backend = 'gloo'
        print("  Using Gloo backend (CPU only)")
    
    # Initialize process group
    os.environ['MASTER_ADDR'] = master_addr
    os.environ['MASTER_PORT'] = str(master_port)
    
    dist.init_process_group(
        backend=backend,
        world_size=world_size,
        rank=rank,
        timeout=timedelta(minutes=30)
    )
    
    return rank, world_size, local_rank

class SimpleModel(nn.Module):
    """Simple CNN for demonstration"""
    def __init__(self, num_classes=10):
        super(SimpleModel, self).__init__()
        self.conv1 = nn.Conv2d(3, 32, kernel_size=3, padding=1)
        self.conv2 = nn.Conv2d(32, 64, kernel_size=3, padding=1)
        self.pool = nn.MaxPool2d(2, 2)
        self.fc1 = nn.Linear(64 * 8 * 8, 128)
        self.fc2 = nn.Linear(128, num_classes)
        self.relu = nn.ReLU()
        self.dropout = nn.Dropout(0.5)
        
    def forward(self, x):
        x = self.pool(self.relu(self.conv1(x)))
        x = self.pool(self.relu(self.conv2(x)))
        x = x.view(-1, 64 * 8 * 8)
        x = self.relu(self.fc1(x))
        x = self.dropout(x)
        x = self.fc2(x)
        return x

def create_data_loaders(batch_size, rank, world_size):
    """Create distributed data loaders"""
    
    # Data preprocessing
    transform = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize((0.5, 0.5, 0.5), (0.5, 0.5, 0.5))
    ])
    
    # Load datasets
    train_dataset = torchvision.datasets.CIFAR10(
        root='./data', train=True, download=(rank == 0), transform=transform)
    test_dataset = torchvision.datasets.CIFAR10(
        root='./data', train=False, download=False, transform=transform)
    
    # Wait for rank 0 to finish downloading
    if world_size > 1:
        dist.barrier()
    
    # Create distributed samplers
    train_sampler = DistributedSampler(
        train_dataset, num_replicas=world_size, rank=rank, shuffle=True)
    test_sampler = DistributedSampler(
        test_dataset, num_replicas=world_size, rank=rank, shuffle=False)
    
    # Create data loaders
    train_loader = DataLoader(
        train_dataset, batch_size=batch_size, sampler=train_sampler,
        num_workers=4, pin_memory=True)
    test_loader = DataLoader(
        test_dataset, batch_size=batch_size, sampler=test_sampler,
        num_workers=4, pin_memory=True)
    
    return train_loader, test_loader, train_sampler

def train_epoch(model, train_loader, criterion, optimizer, epoch, rank, writer):
    """Train for one epoch"""
    model.train()
    running_loss = 0.0
    start_time = time.time()
    
    for batch_idx, (data, target) in enumerate(train_loader):
        if torch.cuda.is_available():
            data, target = data.cuda(), target.cuda()
        
        optimizer.zero_grad()
        output = model(data)
        loss = criterion(output, target)
        loss.backward()
        optimizer.step()
        
        running_loss += loss.item()
        
        # Log progress
        if batch_idx % 100 == 0 and rank == 0:
            print(f'Epoch {epoch}, Batch {batch_idx}, Loss: {loss.item():.6f}')
            
            if writer:
                global_step = epoch * len(train_loader) + batch_idx
                writer.add_scalar('Loss/Train', loss.item(), global_step)
    
    epoch_time = time.time() - start_time
    avg_loss = running_loss / len(train_loader)
    
    if rank == 0:
        print(f'Epoch {epoch} completed in {epoch_time:.2f}s, Avg Loss: {avg_loss:.6f}')
    
    return avg_loss

def validate(model, test_loader, criterion, rank):
    """Validate the model"""
    model.eval()
    test_loss = 0
    correct = 0
    total = 0
    
    with torch.no_grad():
        for data, target in test_loader:
            if torch.cuda.is_available():
                data, target = data.cuda(), target.cuda()
            
            output = model(data)
            test_loss += criterion(output, target).item()
            
            _, predicted = torch.max(output.data, 1)
            total += target.size(0)
            correct += (predicted == target).sum().item()
    
    # Gather metrics from all processes
    if dist.is_initialized():
        metrics = torch.tensor([test_loss, correct, total], dtype=torch.float)
        if torch.cuda.is_available():
            metrics = metrics.cuda()
        
        dist.all_reduce(metrics, op=dist.ReduceOp.SUM)
        test_loss, correct, total = metrics.tolist()
    
    accuracy = 100.0 * correct / total
    avg_loss = test_loss / len(test_loader)
    
    if rank == 0:
        print(f'Test Loss: {avg_loss:.6f}, Accuracy: {accuracy:.2f}%')
    
    return avg_loss, accuracy

def main():
    parser = argparse.ArgumentParser(description='Distributed PyTorch Training')
    parser.add_argument('--epochs', type=int, default=10,
                        help='number of epochs to train')
    parser.add_argument('--batch-size', type=int, default=64,
                        help='input batch size for training')
    parser.add_argument('--lr', type=float, default=0.001,
                        help='learning rate')
    parser.add_argument('--save-model', action='store_true',
                        help='save the trained model')
    parser.add_argument('--log-dir', type=str, default='./logs',
                        help='directory for tensorboard logs')
    
    args = parser.parse_args()
    
    # Initialize distributed training
    rank, world_size, local_rank = setup_distributed()
    
    # Set up logging (only on rank 0)
    writer = None
    if rank == 0:
        writer = SummaryWriter(log_dir=args.log_dir)
        print(f"Starting distributed training with {world_size} processes")
        print(f"Arguments: {args}")
    
    # Create model
    model = SimpleModel(num_classes=10)
    
    # Move model to appropriate device
    if torch.cuda.is_available():
        model = model.cuda(local_rank)
        if world_size > 1:
            model = DDP(model, device_ids=[local_rank])
    elif world_size > 1:
        model = DDP(model)
    
    # Create data loaders
    train_loader, test_loader, train_sampler = create_data_loaders(
        args.batch_size, rank, world_size)
    
    # Define loss and optimizer
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=args.lr)
    scheduler = optim.lr_scheduler.StepLR(optimizer, step_size=5, gamma=0.1)
    
    # Training loop
    start_time = time.time()
    
    for epoch in range(1, args.epochs + 1):
        # Set epoch for distributed sampler
        if world_size > 1:
            train_sampler.set_epoch(epoch)
        
        # Train
        train_loss = train_epoch(model, train_loader, criterion, optimizer, 
                               epoch, rank, writer)
        
        # Validate
        test_loss, accuracy = validate(model, test_loader, criterion, rank)
        
        # Update learning rate
        scheduler.step()
        
        # Log metrics
        if writer and rank == 0:
            writer.add_scalar('Loss/Test', test_loss, epoch)
            writer.add_scalar('Accuracy/Test', accuracy, epoch)
            writer.add_scalar('Learning_Rate', scheduler.get_last_lr()[0], epoch)
    
    total_time = time.time() - start_time
    
    if rank == 0:
        print(f"Training completed in {total_time:.2f} seconds")
        print(f"Average time per epoch: {total_time/args.epochs:.2f} seconds")
        
        # Save model
        if args.save_model:
            model_to_save = model.module if hasattr(model, 'module') else model
            torch.save(model_to_save.state_dict(), 'distributed_model.pth')
            print("Model saved as 'distributed_model.pth'")
        
        if writer:
            writer.close()
    
    # Clean up
    if dist.is_initialized():
        dist.destroy_process_group()

if __name__ == '__main__':
    main()
