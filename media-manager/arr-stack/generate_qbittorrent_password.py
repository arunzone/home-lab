#!/usr/bin/env python3

import hashlib
import os
import base64
import sys
import re

def generate_pbkdf2_password(password):
    """Generate PBKDF2 password for qBittorrent"""
    salt = os.urandom(16)
    iterations = 10000
    
    dk = hashlib.pbkdf2_hmac('sha512', password.encode(), salt, iterations)
    
    return f"@ByteArray(sha512:{iterations}:{base64.b64encode(salt + dk).decode()})"

def update_config_file(config_path, new_password):
    """Update WebUI\\Password_PBKDF2 in qBittorrent config file"""
    try:
        with open(config_path, 'r') as f:
            content = f.read()
        
        # Update the password line
        updated_content = re.sub(
            r'WebUI\\\\Password_PBKDF2=.*',
            f'WebUI\\\\Password_PBKDF2={new_password}',
            content
        )
        
        with open(config_path, 'w') as f:
            f.write(updated_content)
        
        print(f"Updated {config_path} with new password")
        return True
    except Exception as e:
        print(f"Error updating config file: {e}")
        return False

def main():
    # Get password from environment variable
    password = os.getenv('QBITTORRENT_PASSWORD')
    
    if not password:
        print("ERROR: QBITTORRENT_PASSWORD environment variable is not set")
        print("Usage: export QBITTORRENT_PASSWORD='your_password'")
        sys.exit(1)
    
    # Generate PBKDF2 password
    print(f"Generating PBKDF2 password for qBittorrent...")
    pbkdf2_password = generate_pbkdf2_password(password)
    print(f"Generated password: {pbkdf2_password}")
    
    # Update config file
    config_path = "config/qBittorrent/qBittorrent.conf"
    if update_config_file(config_path, pbkdf2_password):
        print("Password successfully updated in qBittorrent config!")
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
