# Lab: Event-Driven Architecture with SNS and S3

## Overview

In this lab, you will build an event-driven data processing pipeline using AWS services. You'll create a FastAPI application running on EC2 that automatically receives notifications whenever new CSV files are uploaded to an S3 bucket. This pattern is fundamental to modern cloud architectures and enables real-time data processing workflows.

However, this example is not particularly "cloud-native" in that it runs within EC2 that will quite likely sit idle 99% of the time. More elegant "serverless" designs will be presented later in the course.

**Key Concepts:**
- Event-driven architecture patterns
- AWS Simple Notification Service (SNS) for message routing
- S3 event notifications
- HTTP endpoints and webhook patterns
- JSON message parsing and handling

**Time Estimate:** 60-90 minutes

## Learning Outcomes

By the end of this lab, you will be able to:

1. **Deploy and configure** a FastAPI application on EC2 to serve as an HTTP endpoint
2. **Create and configure** SNS topics and subscriptions for event routing
3. **Enable S3 event notifications** to trigger messages on object creation
4. **Parse and process** JSON event payloads from AWS services
5. **Debug event-driven workflows** using application logs and AWS console tools
6. **Explain** the benefits and use cases of event-driven vs. polling-based architectures

## Prerequisites

- Personal AWS account
- SSH client and key pair for EC2 access
- AWS CLI configured on your local machine (for testing)
- Basic familiarity with Python and REST APIs

## Architecture Diagram

```
┌─────────────────┐
│   S3 Bucket     │
│  (CSV upload)   │
└────────┬────────┘
         │ Event
         ↓
┌─────────────────┐
│   SNS Topic     │
│   "DS5220"      │
└────────┬────────┘
         │ HTTP POST
         ↓
┌─────────────────┐
│  EC2 Instance   │
│  FastAPI App    │
│  (port 80)      │
└─────────────────┘
```

## Part 1: Set Up the FastAPI Application on EC2

### Step 1.1: Launch EC2 Instance

Launch a new Ubuntu instance in EC2 with the following specifications:

- **AMI:** Ubuntu Server 24.04 LTS or newer
- **Instance Type:** t3.micro (free tier eligible)
- **Security Group:** Allow inbound traffic on:
  - Port 22 (SSH) from your IP
  - Port 80 (HTTP) from Anywhere (0.0.0.0/0) - **required for SNS to reach your endpoint**
- **Storage:** 8 GB (default is fine)

### Step 1.2: Create the FastAPI Application

Create a file named `main.py` with content from [this source](main.py).

This simple API sends and receives JSON data payloads, and its primary purpose
for this lab is to receive or "catch" JSON event messages sent via SNS, which are triggered
whenever new files arrive in S3. The `data/` resource of the API will receive the
notification via an HTTP POST and then parse its contents.

### Step 1.3: Bootstrap Your Instance

Either bootstrap your EC2 instance with the steps below, or SSH into your EC2 instance and manually run the following commands:

```bash
# Update package lists
sudo apt update

# Install Python and FastAPI dependencies
sudo apt install -y python3-pip python3-fastapi uvicorn

# Create application directory
mkdir -p ~/api
cd ~/api

# Create the main.py file (paste the file above)
# or fetch by URL: https://raw.githubusercontent.com/uvasds-systems/ds5220-cloud/refs/heads/main/labs/lab05/main.py
nano main.py
```

### Step 1.4: Start the API Server

Run the FastAPI application. Change be sure you are in the `/home/ubuntu/api/` subdirectory before running this command:

```bash
sudo uvicorn main:app --reload --host 0.0.0.0 --port 80
```

**Important:** Keep this terminal session open. You'll need to see the log output throughout this lab.

### Step 1.5: Test the API

From your local browser, navigate to:

```
http://YOUR-EC2-PUBLIC-IP/
```

You should see:
```json
{"message":"Hello World"}
```

And in your EC2 terminal, you should see a GET request logged.

**✅ Checkpoint 1:** Screenshot showing both your browser with the JSON response AND your EC2 terminal with the corresponding log entry.

## Part 2: Create and Configure SNS Topic

### Step 2.1: Create SNS Topic

1. In the AWS Console, navigate to **Simple Notification Service (SNS)**
2. Click **Topics** in the left sidebar
3. Click **Create topic**
4. Select **Standard** type
5. Name: `DS5220`
6. Display name: `DS5220`
7. Leave other settings as default
8. Click **Create topic**

**Note the Topic ARN** - you'll need this for configuration.

### Step 2.2: Create HTTP Subscription

1. Within your newly created topic, click **Create subscription**
2. Configure the subscription:
   - **Protocol:** HTTP (not HTTPS)
   - **Endpoint:** `http://YOUR-EC2-PUBLIC-IP/data`
   - Leave other settings as default
3. Click **Create subscription**

### Step 2.3: Confirm the Subscription

After creating the subscription:

1. **Check your EC2 terminal** - you should see a `SubscriptionConfirmation` message appear in the logs
2. Look for the `SubscribeURL` in the output
3. **Copy the entire SubscribeURL** (it will be very long)
4. **Open the URL in a new browser tab** to confirm the subscription
5. Return to the SNS console and verify the subscription status changes from "Pending confirmation" to "Confirmed"

**✅ Checkpoint 2:** Screenshot of your SNS subscription showing "Confirmed" status.

## Part 3: Configure S3 Event Notifications

### Step 3.1: Create S3 Bucket

Create a new S3 bucket:

1. Navigate to **S3** in the AWS Console
2. Click **Create bucket**
3. Bucket name: `YOUR-COMPUTING-ID-data` (e.g., `mst3k-data`)
4. Region: Same as your EC2 instance (likely `us-east-1`)
5. Leave other settings as default
6. Click **Create bucket**

### Step 3.2: Configure Event Notifications

1. Click into your new bucket
2. Select the **Properties** tab
3. Scroll down to **Event notifications**
4. Click **Create event notification**

Configure the event:
- **Event name:** `NewCSVFile`
- **Prefix:** (leave blank to watch entire bucket)
- **Suffix:** `.csv`
- **Event types:** Check **All object create events**
- **Destination:** Select **SNS topic**
- **SNS topic:** Select `DS5220` from the dropdown
- Click **Save changes**

**Note:** If you receive a permissions error, AWS will automatically add the necessary bucket policy to allow S3 to publish to SNS.

**✅ Checkpoint 3:** Screenshot of your S3 event notification configuration.

## Part 4: Test the Event-Driven Pipeline

### Step 4.1: Create Test Data

On your **local machine**, create a test script:

```bash
#!/bin/bash

# Create a CSV file with test data
cat > test_upload_$(date +%s).csv << 'EOF'
name,age,city,occupation
Alice Johnson,28,Seattle,Software Engineer
Tanya Smith,35,Austin,Data Scientist
Nina Vanayasi,42,Boston,Product Manager
Carlos Rodriguez,31,Denver,DevOps Engineer
EOF

# Upload to S3 (replace with your bucket name)
aws s3 cp test_upload_*.csv s3://YOUR-BUCKET-NAME/
```

Make it executable and run it:

```bash
chmod +x test_upload.sh
./test_upload.sh
```

### Step 4.2: Observe the Event Flow

Switch back to your EC2 terminal where the FastAPI app is running. You should see:

1. A `Notification` message type
2. Parsed S3 event details including:
   - Event name (ObjectCreated:Put)
   - Bucket name
   - Object key (filename)
   - Event timestamp

**Example output:**
```
================================================================================
Received SNS Message:
{
  "Type": "Notification",
  "MessageId": "b2550f11-729e-5eb4-bbdc-6d16858ccdf4",
  "TopicArn": "arn:aws:sns:us-east-1:440848399208:ds5220",
  "Message": "{\"Records\":[{...}]}"
  ...
}
================================================================================

NOTIFICATION RECEIVED
Event: ObjectCreated:Put
Bucket: mst3k-data
Object: test_upload_1707753729.csv
```

**✅ Checkpoint 4:** Screenshot of your EC2 terminal showing the complete notification with bucket name and object key clearly visible.

### Step 4.3: Upload Multiple Files

Test with different file types and observe what happens:

```bash
# This should trigger a notification
echo "test,data,here" > data.csv
aws s3 cp data.csv s3://YOUR-BUCKET-NAME/

# This should NOT trigger a notification (wrong file extension)
echo "test data" > data.txt
aws s3 cp data.txt s3://YOUR-BUCKET-NAME/

# This should trigger a notification
mkdir -p subfolder
echo "more,test,data" > subfolder/nested.csv
aws s3 cp subfolder/nested.csv s3://YOUR-BUCKET-NAME/subfolder/
```

**✅ Checkpoint 5:** Explain in 2-3 sentences why the .txt file did not trigger a notification.

## Part 5: Extend the Application (Required)

Modify your `main.py` to add the following functionality:

### Step 5.1: Download and Parse CSV Files

Update the `/data` endpoint to:

1. Extract the bucket name and object key from the S3 event
2. Download the CSV file from S3 using boto3
3. Parse the CSV and count the number of rows
4. Log the row count to the console

You'll need to:
- Install boto3: `sudo pip3 install boto3`
- Ensure your EC2 instance has an IAM role with S3 read permissions

**Hint:** Use boto3's S3 client:
```python
import boto3
s3 = boto3.client('s3')
obj = s3.get_object(Bucket=bucket_name, Key=object_key)
```

**✅ Checkpoint 6:** 
- Submit your updated `main.py` code
- Screenshot showing the console output with row count after uploading a CSV

### Step 5.2: Error Handling

Add error handling for:
- Missing or malformed S3 events
- Files that don't exist
- CSV parsing errors

**✅ Checkpoint 7:** Demonstrate your error handling by uploading a malformed CSV file and showing how your application handles it gracefully.

## Part 6: Reflection Questions

Answer the following questions (3-5 sentences each):

1. **Event-Driven vs. Polling:** Compare this event-driven architecture to a polling-based approach where your application checks S3 every 30 seconds for new files. What are the trade-offs?

2. **Scalability:** How would this architecture handle 1,000 CSV files being uploaded simultaneously? What components might become bottlenecks?

3. **Message Delivery:** SNS provides "at-least-once delivery" which means messages might be delivered more than once. How would you modify your application to handle duplicate messages? (Hint: consider idempotency)

4. **Real-World Applications:** Describe a real-world data engineering scenario where this event-driven pattern would be beneficial. What types of data processing would you trigger?

5. **Security Considerations:** Currently, your EC2 instance accepts HTTP traffic from anywhere (0.0.0.0/0) on port 80. What are the security implications? How could you restrict this while still allowing SNS to deliver messages?

## Submission Requirements

Submit a single PDF document containing:

1. All seven checkpoints (screenshots and code as specified)
2. Answers to all five reflection questions
3. Your final `main.py` code (copy/paste into document)
4. A brief summary (1 paragraph) of what you learned and any challenges you encountered.

## Cleanup

To avoid unnecessary charges:

1. Delete your S3 bucket (and all objects within it)
2. Delete your SNS topic
3. Delete your SNS subscription
4. Terminate your EC2 instance

## Troubleshooting Guide

### SNS subscription not confirming
- Check that port 80 is open in your security group to 0.0.0.0/0
- Verify your FastAPI application is running
- Check that you're using HTTP (not HTTPS) for the endpoint
- Look at EC2 terminal logs for incoming requests

### No notification received after S3 upload
- Verify the file extension matches your suffix filter (.csv)
- Check that the SNS subscription is "Confirmed"
- Ensure your S3 event notification is configured correctly
- Review CloudWatch Logs for SNS delivery failures

### Cannot download file from S3 in Part 5
- Ensure your EC2 instance has an IAM role attached
- The IAM role needs `s3:GetObject` permission for your bucket
- Verify boto3 is installed: `pip3 list | grep boto3`

### API not accessible from browser
- Confirm security group allows inbound traffic on port 80
- Verify you're using HTTP (not HTTPS) in your browser
- Check that uvicorn is running: `sudo netstat -tlnp | grep 80`

## Additional Resources

- [AWS SNS Developer Guide](https://docs.aws.amazon.com/sns/latest/dg/welcome.html)
- [S3 Event Notifications](https://docs.aws.amazon.com/AmazonS3/latest/userguide/NotificationHowTo.html)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Event-Driven Architecture Patterns](https://aws.amazon.com/event-driven-architecture/)
