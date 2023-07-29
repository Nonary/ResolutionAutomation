// Code generated using ChatGPT (v4)

using System;
using System.IO;
using System.Text;
using System.Collections.Generic;

public class ReverseFileReader : IDisposable
{
    private const int ChunkSize = 1024;
    private FileStream fs;
    private Queue<string> lineBuffer;
    private bool startOfFileReached;
    private string partialLine;

    public ReverseFileReader(string filePath)
    {
        fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        fs.Position = fs.Length;
        lineBuffer = new Queue<string>();
        startOfFileReached = false;
        partialLine = string.Empty;
    }

    public string ReadLine()
    {
        while (lineBuffer.Count == 0 && !startOfFileReached)
        {
            byte[] chunk = new byte[ChunkSize + 2];
            int chunkSizeToRead = ChunkSize;
            if (fs.Position < ChunkSize)
            {
                startOfFileReached = true;
                chunkSizeToRead = (int)fs.Position;
            }
            fs.Position -= chunkSizeToRead;
            fs.Read(chunk, 0, chunkSizeToRead);
            fs.Position -= chunkSizeToRead;

            string chunkText = Encoding.UTF8.GetString(chunk, 0, chunkSizeToRead);
            string[] lines = chunkText.Split(new string[] { "\n", "\r" }, StringSplitOptions.None);

            lines[0] = partialLine + lines[0];
            partialLine = string.Empty;
            if (!startOfFileReached)
            {
                partialLine = lines[lines.Length - 1];
                Array.Resize(ref lines, lines.Length - 1);
            }

            for (int i = lines.Length - 1; i >= 0; i--)
            {
                lineBuffer.Enqueue(lines[i]);
            }
        }
        return (lineBuffer.Count > 0 ? lineBuffer.Dequeue() : null);
    }

    public void Dispose()
    {
        fs.Dispose();
    }
}
