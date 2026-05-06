#!/bin/bash

set -e

#==============================
# Hadoop WordCount Automation
#==============================
echo "[+] Installing Java (OpenJDK 8)..."
sudo apt update && sudo apt install -y openjdk-8-jdk ssh wget tar

#==============================
# Setup SSH for localhost
#==============================
echo "[+] Configuring SSH for passwordless access..."
ssh-keygen -t rsa -P "" -f ~/.ssh/id_rsa
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Allow SSH to localhost
ssh -o StrictHostKeyChecking=no localhost "echo SSH configured"

#==============================
# Download & Install Hadoop
#==============================
cd ~
echo "[+] Downloading Hadoop 2.7.7..."
wget https://archive.apache.org/dist/hadoop/core/hadoop-2.7.7/hadoop-2.7.7.tar.gz
tar -xzf hadoop-2.7.7.tar.gz
mv hadoop-2.7.7 hadoop

#==============================
# Set Hadoop Environment Variables
#==============================
echo "[+] Configuring environment variables..."
cat <<EOL >> ~/.bashrc
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export HADOOP_HOME=\$HOME/hadoop
export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin
export HADOOP_CONF_DIR=\$HADOOP_HOME/etc/hadoop
EOL

# Export immediately for current shell
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export HADOOP_HOME=$HOME/hadoop
export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop

#==============================
# Configure Hadoop Files
#==============================
echo "[+] Configuring Hadoop XML files..."

cat > $HADOOP_CONF_DIR/core-site.xml <<EOL
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://localhost:9000</value>
  </property>
</configuration>
EOL

cat > $HADOOP_CONF_DIR/hdfs-site.xml <<EOL
<configuration>
  <property>
    <name>dfs.replication</name>
    <value>1</value>
  </property>
</configuration>
EOL

cp $HADOOP_CONF_DIR/mapred-site.xml.template $HADOOP_CONF_DIR/mapred-site.xml
cat > $HADOOP_CONF_DIR/mapred-site.xml <<EOL
<configuration>
  <property>
    <name>mapreduce.framework.name</name>
    <value>yarn</value>
  </property>
</configuration>
EOL

cat > $HADOOP_CONF_DIR/yarn-site.xml <<EOL
<configuration>
  <property>
    <name>yarn.resourcemanager.hostname</name>
    <value>localhost</value>
  </property>
  <property>
    <name>yarn.nodemanager.aux-services</name>
    <value>mapreduce_shuffle</value>
  </property>
</configuration>
EOL

sed -i "s|export JAVA_HOME=.*|export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64|" $HADOOP_CONF_DIR/hadoop-env.sh

#==============================
# Format Namenode & Start Hadoop
#==============================
echo "[+] Formatting HDFS..."
hdfs namenode -format

echo "[+] Starting Hadoop daemons..."
start-dfs.sh
start-yarn.sh
sleep 10

#==============================
# Create WordCount Java File
#==============================
echo "[+] Creating WordCount.java..."
mkdir -p ~/wordcount
cat > ~/wordcount/WordCount.java <<EOL
import java.io.IOException;
import java.util.StringTokenizer;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.Mapper;
import org.apache.hadoop.mapreduce.Reducer;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;

public class WordCount {
  public static class TokenizerMapper extends Mapper<Object, Text, Text, IntWritable> {
    private final static IntWritable one = new IntWritable(1);
    private Text word = new Text();
    public void map(Object key, Text value, Context context) throws IOException, InterruptedException {
      StringTokenizer itr = new StringTokenizer(value.toString());
      while (itr.hasMoreTokens()) {
        word.set(itr.nextToken());
        context.write(word, one);
      }
    }
  }
  public static class IntSumReducer extends Reducer<Text, IntWritable, Text, IntWritable> {
    public void reduce(Text key, Iterable<IntWritable> values, Context context) throws IOException, InterruptedException {
      int sum = 0;
      for (IntWritable val : values) {
        sum += val.get();
      }
      context.write(key, new IntWritable(sum));
    }
  }
  public static void main(String[] args) throws Exception {
    Configuration conf = new Configuration();
    Job job = Job.getInstance(conf, "word count");
    job.setJarByClass(WordCount.class);
    job.setMapperClass(TokenizerMapper.class);
    job.setCombinerClass(IntSumReducer.class);
    job.setReducerClass(IntSumReducer.class);
    job.setOutputKeyClass(Text.class);
    job.setOutputValueClass(IntWritable.class);
    FileInputFormat.addInputPath(job, new Path(args[0]));
    FileOutputFormat.setOutputPath(job, new Path(args[1]));
    System.exit(job.waitForCompletion(true) ? 0 : 1);
  }
}
EOL

#==============================
# Compile Java & Create JAR
#==============================
echo "[+] Compiling WordCount.java..."
mkdir -p ~/wordcount/classes
javac -classpath `hadoop classpath` -d ~/wordcount/classes ~/wordcount/WordCount.java
jar -cvf ~/wordcount/wordcount.jar -C ~/wordcount/classes/ .

#==============================
# Create Input & Run Job
#==============================
echo "[+] Creating sample input..."
echo "Hello Hadoop Hello MapReduce Hadoop" > ~/wordcount/input.txt
hdfs dfs -mkdir -p /wordcount/input
hdfs dfs -put -f ~/wordcount/input.txt /wordcount/input

#==============================
# Run MapReduce WordCount Job
#==============================
echo "[+] Running WordCount job..."
hadoop jar ~/wordcount/wordcount.jar WordCount /wordcount/input /wordcount/output

#==============================
# View Output
#==============================
echo "[+] Job Output:"
hdfs dfs -cat /wordcount/output/part-r-00000

echo "========== SCRIPT COMPLETED SUCCESSFULLY =========="