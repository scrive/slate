
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.ByteArrayOutputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Map;

import com.itextpdf.text.DocumentException;
import com.itextpdf.text.Element;
import com.itextpdf.text.pdf.BaseFont;
import com.itextpdf.text.pdf.PdfContentByte;
import com.itextpdf.text.pdf.PdfReader;
import com.itextpdf.text.pdf.PdfStamper;
import com.itextpdf.text.pdf.PdfWriter;
import com.itextpdf.text.Rectangle;
import com.itextpdf.text.pdf.PdfSmartCopy;
import com.itextpdf.text.pdf.PdfCopy;
import com.itextpdf.text.Document;
import com.itextpdf.text.Paragraph;
import com.itextpdf.text.pdf.PdfImportedPage;
import com.itextpdf.text.Font;
import com.itextpdf.text.BaseColor;
import com.itextpdf.text.Rectangle;
import com.itextpdf.text.pdf.PdfPCell;
import com.itextpdf.text.pdf.PdfPTable;
import com.itextpdf.text.Phrase;


class HistEntry {
    public String histdate;
    public String histcomment;
    public String histaddress;
}

class Person {

    public String fullname;
    public String company;
    public String personalnumber;
    public String companynumber;
    public String email;
    public Boolean fullnameverified;
    public Boolean companyverified;
    public Boolean numberverified;
    public Boolean emailverified;
    public ArrayList<Field> fields;

}

class Field {
    public String valueBase64;
    public String value;
    public Double x, y;
    public int page;
    public double image_w;
    public double image_h;
    public int internal_image_w;
    public int internal_image_h;
    public Boolean includeInSummary;
    public Boolean onlyForSummary;
    public ArrayList<Integer> keyColor;
}

class SealSpec {
    public String input;
    public String output;
    public String documentNumber;
    public ArrayList<Person> persons;
    public ArrayList<Person> secretaries;
    public ArrayList<HistEntry> history;
    public String initials;
    public String hostpart;
    public Map<String,String> staticTexts;
    public ArrayList<SealAttachment> attachments;
    public ArrayList<SealAttachment> filesList;
    }

class SealAttachment {
    public String fileName;
    public String mimeType;
    public String fileBase64Content;
}

public class AppendMode {
    /** The resulting PDF. */
    public static final String RESULT
        = "appended.pdf";
    public static final String INPUT
        = "input.pdf";


    public void prepareSealPages(OutputStream os)
        throws IOException, DocumentException {

        Document document = new Document();
        PdfWriter writer = PdfWriter.getInstance(document, os);

        document.open();

        BaseFont bf;
        Font font;
        bf = BaseFont.createFont("STSong-Light", "UniGB-UCS2-H", BaseFont.EMBEDDED);

        font = new Font(bf, 12);

        // step 4
        document.newPage();
        document.add(new Paragraph("This page will NOT be followed by a blank page! \u5341\u950a\u57cb\u4f0f", font));
        document.newPage();
        // we don't add anything to this page: newPage() will be ignored
        document.newPage();
        document.add(new Paragraph("This page will be followed by a blank page!"));
        document.newPage();
        writer.setPageEmpty(false);
        document.newPage();
        document.add(new Paragraph("The previous page was a blank page!"));


        PdfPTable table = new PdfPTable(3);
        table.setWidthPercentage(288 / 5.23f);
        table.setWidths(new int[]{2, 1, 1});
        PdfPCell cell;
        cell = new PdfPCell(new Phrase("Table 1"));
        cell.setColspan(3);
        table.addCell(cell);
        cell = new PdfPCell(new Phrase("Cell with rowspan 2"));
        cell.setRowspan(2);
        cell.setBorder(Rectangle.LEFT | Rectangle.TOP | Rectangle.RIGHT);
        cell.setBorderColor(BaseColor.CYAN);
        cell.setBorderWidth(5);

        table.addCell(cell);
        table.addCell("row 1; cell 1");
        table.addCell("row 1; cell 2");
        table.addCell("row 2; cell 1");
        table.addCell("row 2; cell 2");
        document.add(table);

        // step 5
        document.close();
    }

    /**
     * Manipulates a PDF file src with the file dest as result
     * @param src the original PDF
     * @param dest the resulting PDF
     * @throws IOException
     * @throws DocumentException
     */
    public void manipulatePdf(String src, String dest) throws IOException, DocumentException {

        ByteArrayOutputStream os = new ByteArrayOutputStream();

        prepareSealPages(os);


        // step 1
        Document document = new Document();
        // step 2
        PdfCopy writer
            = new PdfSmartCopy(document, new FileOutputStream(dest));

        document.open();

        PdfReader reader = new PdfReader(src);
        int count = reader.getNumberOfPages();
        for( int i=1; i<=count; i++ ) {
            PdfImportedPage page = writer.getImportedPage(reader, i);
            writer.addPage(page);
        }
        writer.freeReader(reader);
        reader.close();

        reader = new PdfReader(os.toByteArray());
        count = reader.getNumberOfPages();
        for( int i=1; i<=count; i++ ) {
            PdfImportedPage page = writer.getImportedPage(reader, i);
            writer.addPage(page);
        }
        writer.freeReader(reader);

        reader.close();

        document.close();
    }

    /**
     * Main method.
     *
     * @param    args    no arguments needed
     * @throws DocumentException
     * @throws IOException
     */
    public static void main(String[] args) throws IOException, DocumentException {
        new AppendMode().manipulatePdf(INPUT, RESULT);
    }
}
