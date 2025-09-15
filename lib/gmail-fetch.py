#!/usr/bin/env python3
"""
Gmail API Integration for ccOS Agents
Provides full email reading, sending, and management capabilities
"""

import os
import sys
import json
import base64
import email
from pathlib import Path
from datetime import datetime, timedelta
import argparse

# Gmail API imports
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

class GmailAPI:
    def __init__(self):
        self.SCOPES = [
            'https://www.googleapis.com/auth/gmail.readonly',
            'https://www.googleapis.com/auth/gmail.send',
            'https://www.googleapis.com/auth/gmail.compose',
            'https://www.googleapis.com/auth/gmail.modify'
        ]
        self.service = None
        self.creds_dir = Path.home() / '.claude' / 'gmail'
        self.creds_dir.mkdir(parents=True, exist_ok=True)
        
    def authenticate(self):
        """Handle Gmail API authentication"""
        creds = None
        token_path = self.creds_dir / 'token.json'
        credentials_path = self.creds_dir / 'credentials.json'
        
        # Load existing token
        if token_path.exists():
            creds = Credentials.from_authorized_user_file(str(token_path), self.SCOPES)
        
        # If no valid credentials, get new ones
        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
            else:
                if not credentials_path.exists():
                    print(f"❌ Gmail credentials not found!")
                    print(f"Please download 'credentials.json' from Google Cloud Console and place it at:")
                    print(f"   {credentials_path}")
                    print(f"\nSetup Guide:")
                    print(f"1. Go to https://console.cloud.google.com/")
                    print(f"2. Create/select project")  
                    print(f"3. Enable Gmail API")
                    print(f"4. Create OAuth 2.0 credentials (Desktop application)")
                    print(f"5. Download credentials.json")
                    return False
                    
                flow = InstalledAppFlow.from_client_secrets_file(
                    str(credentials_path), self.SCOPES)
                
                # Try manual flow for headless environments
                try:
                    creds = flow.run_local_server(port=0)
                except Exception as e:
                    print("❌ Local server authentication failed (headless environment)")
                    print("📋 Manual OAuth setup required:")
                    print(f"1. Go to: {flow.authorization_url()[0]}")
                    print("2. Authorize the application")
                    print("3. Copy the authorization code")
                    print("4. Run: ./lib/gmail-fetch.sh auth-code <CODE>")
                    return False
            
            # Save credentials for next run
            with open(token_path, 'w') as token:
                token.write(creds.to_json())
        
        try:
            self.service = build('gmail', 'v1', credentials=creds)
            return True
        except Exception as e:
            print(f"❌ Gmail API authentication failed: {e}")
            return False
    
    def get_unread_emails(self, limit=10, sender_filter=None, subject_filter=None):
        """Get unread emails with optional filters"""
        try:
            query = 'is:unread'
            if sender_filter:
                query += f' from:{sender_filter}'
            if subject_filter:
                query += f' subject:{subject_filter}'
            
            results = self.service.users().messages().list(
                userId='me', q=query, maxResults=limit).execute()
            
            messages = results.get('messages', [])
            emails = []
            
            for message in messages:
                msg = self.service.users().messages().get(
                    userId='me', id=message['id']).execute()
                
                email_data = self._parse_email(msg)
                emails.append(email_data)
            
            return emails
            
        except HttpError as error:
            print(f"❌ Error fetching emails: {error}")
            return []
    
    def get_emails_by_filter(self, days=7, limit=50, query_filter=""):
        """Get emails by custom filter within specified days"""
        try:
            # Calculate date for filtering
            since_date = datetime.now() - timedelta(days=days)
            date_str = since_date.strftime('%Y/%m/%d')
            
            query = f'after:{date_str}'
            if query_filter:
                query += f' {query_filter}'
            
            results = self.service.users().messages().list(
                userId='me', q=query, maxResults=limit).execute()
            
            messages = results.get('messages', [])
            emails = []
            
            for message in messages:
                msg = self.service.users().messages().get(
                    userId='me', id=message['id']).execute()
                
                email_data = self._parse_email(msg)
                emails.append(email_data)
            
            return emails
            
        except HttpError as error:
            print(f"❌ Error fetching emails: {error}")
            return []
    
    def send_email(self, to_email, subject, body, is_html=True, reply_to_id=None):
        """Send email via Gmail API"""
        try:
            if is_html:
                message = MIMEMultipart('alternative')
                html_part = MIMEText(body, 'html')
                message.attach(html_part)
            else:
                message = MIMEText(body)
            
            message['to'] = to_email
            message['subject'] = subject
            
            # Handle reply threading
            if reply_to_id:
                message['In-Reply-To'] = reply_to_id
                message['References'] = reply_to_id
            
            raw_message = base64.urlsafe_b64encode(message.as_bytes()).decode()
            
            send_message = {'raw': raw_message}
            if reply_to_id:
                send_message['threadId'] = reply_to_id
            
            result = self.service.users().messages().send(
                userId='me', body=send_message).execute()
            
            return {
                'success': True,
                'message_id': result['id'],
                'thread_id': result.get('threadId')
            }
            
        except HttpError as error:
            return {
                'success': False,
                'error': str(error)
            }
    
    def mark_as_read(self, message_id):
        """Mark email as read"""
        try:
            self.service.users().messages().modify(
                userId='me',
                id=message_id,
                body={'removeLabelIds': ['UNREAD']}
            ).execute()
            return True
        except HttpError as error:
            print(f"❌ Error marking email as read: {error}")
            return False
    
    def _parse_email(self, msg):
        """Parse Gmail API message into structured data"""
        headers = msg['payload'].get('headers', [])
        
        # Extract headers
        email_data = {
            'id': msg['id'],
            'thread_id': msg['threadId'],
            'snippet': msg['snippet'],
            'date': None,
            'from': None,
            'to': None,
            'subject': None,
            'body': '',
            'is_html': False
        }
        
        for header in headers:
            name = header['name'].lower()
            if name == 'date':
                email_data['date'] = header['value']
            elif name == 'from':
                email_data['from'] = header['value']
            elif name == 'to':
                email_data['to'] = header['value']
            elif name == 'subject':
                email_data['subject'] = header['value']
        
        # Extract body
        email_data['body'] = self._get_message_body(msg['payload'])
        
        return email_data
    
    def _get_message_body(self, payload):
        """Extract email body from payload"""
        body = ""
        
        if 'parts' in payload:
            for part in payload['parts']:
                if part['mimeType'] == 'text/plain':
                    data = part['body']['data']
                    body = base64.urlsafe_b64decode(data).decode('utf-8')
                    break
                elif part['mimeType'] == 'text/html':
                    data = part['body']['data']
                    body = base64.urlsafe_b64decode(data).decode('utf-8')
                    break
        else:
            if payload['mimeType'] == 'text/plain':
                data = payload['body']['data']
                body = base64.urlsafe_b64decode(data).decode('utf-8')
            elif payload['mimeType'] == 'text/html':
                data = payload['body']['data']
                body = base64.urlsafe_b64decode(data).decode('utf-8')
        
        return body
    
    def get_profile_info(self):
        """Get Gmail profile information"""
        try:
            profile = self.service.users().getProfile(userId='me').execute()
            return {
                'email': profile['emailAddress'],
                'messages_total': profile['messagesTotal'],
                'threads_total': profile['threadsTotal']
            }
        except HttpError as error:
            print(f"❌ Error getting profile: {error}")
            return None

def main():
    parser = argparse.ArgumentParser(description='Gmail API for ccOS Agents')
    parser.add_argument('command', choices=[
        'setup-check', 'unread', 'send', 'filter', 'profile', 
        'mark-read', 'customer-support', 'investor-emails', 'auth-url', 'auth-code'
    ])
    parser.add_argument('--to', help='Recipient email for sending')
    parser.add_argument('--subject', help='Email subject')
    parser.add_argument('--body', help='Email body content')
    parser.add_argument('--html', action='store_true', help='Send as HTML')
    parser.add_argument('--limit', type=int, default=10, help='Number of emails to fetch')
    parser.add_argument('--days', type=int, default=7, help='Days to look back')
    parser.add_argument('--filter', help='Custom filter query')
    parser.add_argument('--sender', help='Filter by sender')
    parser.add_argument('--message-id', help='Message ID to mark as read')
    parser.add_argument('--code', help='Authorization code for manual OAuth')
    
    args = parser.parse_args()
    
    gmail = GmailAPI()
    
    # Handle auth commands without authentication
    if args.command in ['auth-url', 'auth-code']:
        pass  # Skip authentication for these commands
    else:
        if not gmail.authenticate():
            sys.exit(1)
    
    if args.command == 'setup-check':
        profile = gmail.get_profile_info()
        if profile:
            print(f"✅ Gmail API connected successfully!")
            print(f"📧 Email: {profile['email']}")
            print(f"📊 Total Messages: {profile['messages_total']}")
            print(f"🧵 Total Threads: {profile['threads_total']}")
        else:
            print("❌ Gmail API setup failed")
            sys.exit(1)
    
    elif args.command == 'unread':
        emails = gmail.get_unread_emails(
            limit=args.limit,
            sender_filter=args.sender,
            subject_filter=args.filter
        )
        
        print(f"📧 Found {len(emails)} unread emails:")
        for email_data in emails:
            print(f"\n🔹 From: {email_data['from']}")
            print(f"   Subject: {email_data['subject']}")
            print(f"   Date: {email_data['date']}")
            print(f"   Preview: {email_data['snippet'][:100]}...")
            print(f"   ID: {email_data['id']}")
    
    elif args.command == 'filter':
        emails = gmail.get_emails_by_filter(
            days=args.days,
            limit=args.limit,
            query_filter=args.filter or ""
        )
        
        print(f"📧 Found {len(emails)} emails matching filter:")
        for email_data in emails:
            print(f"\n🔹 From: {email_data['from']}")
            print(f"   Subject: {email_data['subject']}")
            print(f"   Date: {email_data['date']}")
            print(f"   Preview: {email_data['snippet'][:100]}...")
    
    elif args.command == 'customer-support':
        # Look for customer support emails
        support_keywords = [
            'support', 'help', 'issue', 'problem', 'bug', 'question',
            'inquiry', 'contact', 'assistance', 'trouble'
        ]
        
        filter_query = ' OR '.join([f'subject:{keyword}' for keyword in support_keywords])
        emails = gmail.get_emails_by_filter(
            days=args.days,
            limit=args.limit,
            query_filter=filter_query
        )
        
        print(f"🎧 Found {len(emails)} potential customer support emails:")
        for email_data in emails:
            print(f"\n🔹 From: {email_data['from']}")
            print(f"   Subject: {email_data['subject']}")
            print(f"   Date: {email_data['date']}")
            print(f"   Preview: {email_data['snippet'][:150]}...")
            print(f"   ID: {email_data['id']}")
    
    elif args.command == 'investor-emails':
        # Look for investor-related emails
        investor_keywords = [
            'investment', 'funding', 'investor', 'venture', 'capital',
            'partnership', 'acquisition', 'valuation', 'pitch', 'deck'
        ]
        
        filter_query = ' OR '.join([f'subject:{keyword}' for keyword in investor_keywords])
        emails = gmail.get_emails_by_filter(
            days=args.days,
            limit=args.limit,
            query_filter=filter_query
        )
        
        print(f"💰 Found {len(emails)} potential investor emails:")
        for email_data in emails:
            print(f"\n🔹 From: {email_data['from']}")
            print(f"   Subject: {email_data['subject']}")
            print(f"   Date: {email_data['date']}")
            print(f"   Preview: {email_data['snippet'][:150]}...")
            print(f"   ID: {email_data['id']}")
    
    elif args.command == 'send':
        if not args.to or not args.subject or not args.body:
            print("❌ Missing required arguments: --to, --subject, --body")
            sys.exit(1)
        
        result = gmail.send_email(
            to_email=args.to,
            subject=args.subject,
            body=args.body,
            is_html=args.html
        )
        
        if result['success']:
            print(f"✅ Email sent successfully!")
            print(f"   Message ID: {result['message_id']}")
            print(f"   Thread ID: {result.get('thread_id')}")
        else:
            print(f"❌ Failed to send email: {result['error']}")
            sys.exit(1)
    
    elif args.command == 'mark-read':
        if not args.message_id:
            print("❌ Missing required argument: --message-id")
            sys.exit(1)
        
        if gmail.mark_as_read(args.message_id):
            print(f"✅ Email marked as read: {args.message_id}")
        else:
            print(f"❌ Failed to mark email as read")
            sys.exit(1)
    
    elif args.command == 'profile':
        profile = gmail.get_profile_info()
        if profile:
            print(json.dumps(profile, indent=2))
        else:
            print("❌ Failed to get profile information")
            sys.exit(1)
    
    elif args.command == 'auth-url':
        # Generate authorization URL for manual OAuth
        credentials_path = gmail.creds_dir / 'credentials.json'
        if not credentials_path.exists():
            print("❌ Gmail credentials not found!")
            sys.exit(1)
            
        flow = InstalledAppFlow.from_client_secrets_file(
            str(credentials_path), gmail.SCOPES)
        flow.redirect_uri = 'http://localhost'
        auth_url, _ = flow.authorization_url(prompt='consent')
        
        print("🌐 Manual OAuth Setup:")
        print(f"1. Go to: {auth_url}")
        print("2. Authorize the application")
        print("3. Copy the authorization code from the URL")
        print("4. Run: ./lib/gmail-fetch.sh auth-code --code <AUTHORIZATION_CODE>")
    
    elif args.command == 'auth-code':
        if not args.code:
            print("❌ Missing required argument: --code")
            sys.exit(1)
            
        # Complete manual OAuth flow
        credentials_path = gmail.creds_dir / 'credentials.json'
        token_path = gmail.creds_dir / 'token.json'
        
        flow = InstalledAppFlow.from_client_secrets_file(
            str(credentials_path), gmail.SCOPES)
        flow.redirect_uri = 'http://localhost'
        
        try:
            flow.fetch_token(code=args.code)
            creds = flow.credentials
            
            # Save credentials
            with open(token_path, 'w') as token:
                token.write(creds.to_json())
                
            print("✅ Gmail API authentication successful!")
            print("🎯 Run './lib/gmail-fetch.sh setup-check' to verify")
            
        except Exception as e:
            print(f"❌ Authentication failed: {e}")
            sys.exit(1)

if __name__ == '__main__':
    main()